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

const http = require('http');
const https = require('https');
const WebSocket = require('ws');

const PORT = process.env.PORT || 8080;

// Create a barebones HTTP server for Keep-Alive/Uptime pings
const server = http.createServer((req, res) => {
  if (req.url === '/' || req.url === '/ping') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('pong');
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

const wss = new WebSocket.Server({ server });

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

server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
  console.log(`Active rooms: checked every 30s`);
});

// Keep-Alive Hack: Self-ping every 14 minutes to prevent Render free-tier sleep
setInterval(() => {
  // RENDER_EXTERNAL_URL is automatically set by Render
  const url = process.env.RENDER_EXTERNAL_URL || `http://localhost:${PORT}`;
  const lib = url.startsWith('https') ? https : http;
  
  lib.get(url, (res) => {
    // Consume response data to free up memory
    res.on('data', () => {});
    res.on('end', () => {
      console.log(`[Keep-Alive] Pinged ${url}, status: ${res.statusCode}`);
    });
  }).on('error', (err) => {
    console.error(`[Keep-Alive] Error pinging ${url}:`, err.message);
  });
}, 14 * 60 * 1000); // 14 mins
