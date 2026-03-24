// lib/core/network/signaling_service.dart
// PHASE 4 — Signaling (WebSocket relay, stateless, no message storage)
//
// 3 signaling servers deployed on 3 separate Render.com free accounts.
// Each user is randomly assigned one on app launch.
// If assigned server is down, automatically tries the next one.
// Relay is used ONLY for ICE offer/answer exchange — never for messages.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

// ── Server pool ───────────────────────────────────────────────────────────────
// TODO: Replace these with your 3 actual Render.com deployment URLs after deploy.
const _signalingPool = [
  'wss://securemsg.onrender.com',
  'wss://securemsg-rxfo.onrender.com',
  'wss://securemsg-noz7.onrender.com',
];

// ── TURN server pool ──────────────────────────────────────────────────────────
// 3 providers, users randomly assigned. All free tier.
// TODO: Fill in your credentials after creating accounts at each provider.
final _turnPool = [
  _TurnServer(
    // metered.ca — 50 GB/month free
    url: 'turn:relay.metered.ca:80',
    username: 'YOUR_METERED_USERNAME',
    credential: 'YOUR_METERED_CREDENTIAL',
  ),
  _TurnServer(
    // Cloudflare Calls — 1000 min/month free
    url: 'turn:turn.cloudflare.com:3478',
    username: 'YOUR_CF_USERNAME',
    credential: 'YOUR_CF_CREDENTIAL',
  ),
  _TurnServer(
    // openrelay.metered.ca — community free tier (backup)
    url: 'turn:openrelay.metered.ca:80',
    username: 'openrelayproject',
    credential: 'openrelayproject',
  ),
];

class _TurnServer {
  final String url;
  final String username;
  final String credential;
  const _TurnServer({required this.url, required this.username, required this.credential});
}

// ── ICE config builder ────────────────────────────────────────────────────────

/// Returns a WebRTC ICE config with STUN + one randomly assigned TURN server.
Map<String, dynamic> buildIceConfig() {
  final turn = _turnPool[Random().nextInt(_turnPool.length)];
  return {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': turn.url,
        'username': turn.username,
        'credential': turn.credential,
      },
    ],
    'iceCandidatePoolSize': 10,
  };
}

// ── Signaling message types ───────────────────────────────────────────────────

enum SigMsgType { join, offer, answer, candidate, leave }

class SigMessage {
  final SigMsgType type;
  final String room;       // SHA256(min(pkA,pkB) + max(pkA,pkB)) — deterministic
  final Map<String, dynamic> data;

  SigMessage({required this.type, required this.room, required this.data});

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'room': room,
    'data': data,
  };

  factory SigMessage.fromJson(Map<String, dynamic> j) => SigMessage(
    type: SigMsgType.values.byName(j['type'] as String),
    room: j['room'] as String,
    data: j['data'] as Map<String, dynamic>,
  );
}

// ── Signaling service ─────────────────────────────────────────────────────────

typedef SigHandler = void Function(SigMessage msg);

class SignalingService {
  SignalingService._();
  static final instance = SignalingService._();

  WebSocketChannel? _ws;
  String? _currentServer;
  String? _currentRoom;
  SigHandler? _onMessage;
  Timer? _pingTimer;
  bool _connected = false;

  final _rand = Random();

  // ── Connect ───────────────────────────────────────────────────────────────

  /// Connect to a random signaling server. Falls back to next if unreachable.
  Future<void> connect({
    required String room,
    required SigHandler onMessage,
  }) async {
    _currentRoom = room;
    _onMessage   = onMessage;

    final servers = List<String>.from(_signalingPool)..shuffle(_rand);
    for (final url in servers) {
      try {
        await _connectTo(url, room);
        return; // success
      } catch (_) {
        continue; // try next server
      }
    }
    throw Exception('All signaling servers unreachable');
  }

  Future<void> _connectTo(String url, String room) async {
    final wsUrl = Uri.parse('$url?room=${Uri.encodeComponent(room)}');
    _ws = WebSocketChannel.connect(wsUrl);

    // Await handshake
    await _ws!.ready;
    _connected = true;
    _currentServer = url;

    // Send join
    send(SigMessage(type: SigMsgType.join, room: room, data: {}));

    // Listen
    _ws!.stream.listen(
      (raw) {
        try {
          final msg = SigMessage.fromJson(jsonDecode(raw as String));
          _onMessage?.call(msg);
        } catch (_) {}
      },
      onDone: _onDisconnected,
      onError: (_) => _onDisconnected(),
    );

    // Keepalive ping every 25s (Render.com closes idle WS after 30s)
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connected) _ws?.sink.add('ping');
    });
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  void send(SigMessage msg) {
    if (!_connected) return;
    _ws?.sink.add(jsonEncode(msg.toJson()));
  }

  void sendOffer(String sdp)               => send(SigMessage(type: SigMsgType.offer,     room: _currentRoom!, data: {'sdp': sdp}));
  void sendAnswer(String sdp)              => send(SigMessage(type: SigMsgType.answer,    room: _currentRoom!, data: {'sdp': sdp}));
  void sendCandidate(Map<String, dynamic> c) => send(SigMessage(type: SigMsgType.candidate, room: _currentRoom!, data: c));

  // ── Disconnect / reconnect ────────────────────────────────────────────────

  void _onDisconnected() {
    _connected = false;
    _pingTimer?.cancel();
    // Auto-reconnect after 3s
    Timer(const Duration(seconds: 3), () {
      if (_currentRoom != null && _onMessage != null) {
        connect(room: _currentRoom!, onMessage: _onMessage!);
      }
    });
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _connected = false;
    await _ws?.sink.close();
    _ws = null;
  }

  bool get isConnected => _connected;
}
