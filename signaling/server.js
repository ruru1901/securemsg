// signaling/server.js
// Stateless WebSocket signaling relay.
// Deploy this SAME file to 3 separate Render.com free accounts:
//   securemsg-sig-1.onrender.com
//   securemsg-sig-2.onrender.com
//   securemsg-sig-3.onrender.com
//
// No database. No message storage. Messages relayed in memory only.
// Rooms auto-cleaned when both peers disconnect.
// Render.com free tier: always-on, no credit card required.

const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;
const wss  = new WebSocket.Server({ port: PORT });

// rooms: Map<roomId, Set<WebSocket>>
const rooms = new Map();

wss.on('connection', (ws, req) => {
  // Room ID passed as query param: ws://host?room=ROOM_ID
  const url    = new URL(req.url, 'ws://localhost');
  const roomId = url.searchParams.get('room');

  if (!roomId) {
    ws.close(4000, 'Missing room param');
    return;
  }

  ws._room = roomId;
  ws._alive = true;

  // Join room
  if (!rooms.has(roomId)) rooms.set(roomId, new Set());
  rooms.get(roomId).add(ws);

  console.log(`[+] room=${roomId} peers=${rooms.get(roomId).size}`);

  ws.on('message', (raw) => {
    // Ignore keepalive pings
    if (raw === 'ping' || raw.toString() === 'ping') {
      ws.send('pong');
      return;
    }

    // Relay to all OTHER peers in the same room
    const peers = rooms.get(ws._room);
    if (!peers) return;

    for (const peer of peers) {
      if (peer !== ws && peer.readyState === WebSocket.OPEN) {
        peer.send(raw);
      }
    }
  });

  ws.on('pong', () => { ws._alive = true; });

  ws.on('close', () => {
    _leaveRoom(ws);
    console.log(`[-] room=${roomId}`);
  });

  ws.on('error', () => _leaveRoom(ws));
});

function _leaveRoom(ws) {
  if (!ws._room) return;
  const peers = rooms.get(ws._room);
  if (!peers) return;
  peers.delete(ws);
  if (peers.size === 0) rooms.delete(ws._room);
}

// Heartbeat: terminate truly dead connections every 30s
// (Render.com closes idle WS after 55s — we ping at 25s from client side)
setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws._alive) { ws.terminate(); return; }
    ws._alive = false;
    ws.ping();
  });
}, 30_000);

console.log(`Signaling server running on port ${PORT}`);
console.log(`Active rooms: checked every 30s`);
