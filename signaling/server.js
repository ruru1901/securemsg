const WebSocket = require('ws');
const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('SecureMsg signaling server OK');
});

const wss = new WebSocket.Server({ server });
const rooms = new Map();

wss.on('connection', (ws) => {
  let myRoom = null;

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);
      if (msg.type === 'join') {
        myRoom = msg.room;
        if (!rooms.has(myRoom)) rooms.set(myRoom, new Set());
        rooms.get(myRoom).add(ws);
      } else if (myRoom) {
        const peers = rooms.get(myRoom);
        if (peers) {
          peers.forEach(peer => {
            if (peer !== ws && peer.readyState === WebSocket.OPEN) {
              peer.send(data);
            }
          });
        }
      }
    } catch (e) { }
  });

  ws.on('close', () => {
    if (myRoom && rooms.has(myRoom)) {
      rooms.get(myRoom).delete(ws);
      if (rooms.get(myRoom).size === 0) rooms.delete(myRoom);
    }
  });

  const heartbeat = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) ws.ping();
  }, 30000);

  ws.on('close', () => clearInterval(heartbeat));
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
});