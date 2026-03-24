// lib/core/network/p2p_connection.dart
// PHASE 5 — WebRTC P2P connection
//
// One RTCPeerConnection per contact (lazy-created).
// Data channel: ordered, reliable — text + media chunks.
// Audio track: added on-demand for VoIP calls.
// On disconnect: auto-reconnects via signaling relay.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_service.dart';

enum PeerState { disconnected, connecting, connected, failed }

typedef DataHandler  = void Function(Uint8List data);
typedef StateHandler = void Function(PeerState state);

class P2PConnection {
  final String contactId;
  final String peerPubKey;
  final String localPubKey;

  P2PConnection({
    required this.contactId,
    required this.peerPubKey,
    required this.localPubKey,
  });

  RTCPeerConnection? _pc;
  RTCDataChannel?   _dc;
  MediaStream?      _localAudio;
  bool _isInitiator = false;

  DataHandler?  onData;
  StateHandler? onStateChange;
  PeerState _state = PeerState.disconnected;
  PeerState get state => _state;

  /// Deterministic room ID — same for both peers
  String get _room {
    final keys = [localPubKey, peerPubKey]..sort();
    return '${keys[0]}_${keys[1]}';
  }

  // ── Initiator side (after QR scan) ───────────────────────────────────────

  Future<void> connectAsInitiator() async {
    _isInitiator = true;
    _setState(PeerState.connecting);
    await _setupSignaling();
    _pc = await createPeerConnection(buildIceConfig());
    _setupPCHandlers();
    _dc = await _pc!.createDataChannel(
      'msg',
      RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30,
    );
    _setupDCHandlers(_dc!);
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    SignalingService.instance.sendOffer(offer.sdp!);
  }

  // ── Responder side (waits for offer) ─────────────────────────────────────

  Future<void> connectAsResponder() async {
    _isInitiator = false;
    _setState(PeerState.connecting);
    await _setupSignaling();
    _pc = await createPeerConnection(buildIceConfig());
    _setupPCHandlers();
    _pc!.onDataChannel = (ch) {
      _dc = ch;
      _setupDCHandlers(ch);
    };
  }

  Future<void> _setupSignaling() => SignalingService.instance.connect(
        room: _room,
        onMessage: _handleSig,
      );

  // ── Signaling handler ─────────────────────────────────────────────────────

  void _handleSig(SigMessage msg) async {
    switch (msg.type) {
      case SigMsgType.offer:
        if (_isInitiator) return;
        await _pc?.setRemoteDescription(RTCSessionDescription(msg.data['sdp'] as String, 'offer'));
        final ans = await _pc!.createAnswer();
        await _pc!.setLocalDescription(ans);
        SignalingService.instance.sendAnswer(ans.sdp!);
        break;
      case SigMsgType.answer:
        if (!_isInitiator) return;
        await _pc?.setRemoteDescription(RTCSessionDescription(msg.data['sdp'] as String, 'answer'));
        break;
      case SigMsgType.candidate:
        await _pc?.addCandidate(RTCIceCandidate(
          msg.data['candidate'] as String?,
          msg.data['sdpMid'] as String?,
          msg.data['sdpMLineIndex'] as int?,
        ));
        break;
      default:
        break;
    }
  }

  // ── Peer connection handlers ──────────────────────────────────────────────

  void _setupPCHandlers() {
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) {
        SignalingService.instance.sendCandidate({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(PeerState.connected);
        SignalingService.instance.disconnect(); // drop relay, P2P active
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setState(PeerState.disconnected);
        _scheduleReconnect();
      }
    };
  }

  void _setupDCHandlers(RTCDataChannel dc) {
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _setState(PeerState.connected);
      }
    };
    dc.onMessage = (m) {
      if (m.isBinary) onData?.call(m.binary);
    };
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  bool get canSend =>
      _state == PeerState.connected &&
      _dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  /// Returns true if sent, false if queued to outbox.
  Future<bool> send(Uint8List frame) async {
    if (!canSend) return false;
    _dc!.send(RTCDataChannelMessage.fromBinary(frame));
    return true;
  }

  // ── VoIP ──────────────────────────────────────────────────────────────────

  Future<void> startCall() async {
    _localAudio = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    for (final t in _localAudio!.getAudioTracks()) {
      await _pc?.addTrack(t, _localAudio!);
    }
  }

  Future<void> endCall() async {
    _localAudio?.getTracks().forEach((t) => t.stop());
    await _localAudio?.dispose();
    _localAudio = null;
  }

  // ── Auto-reconnect ────────────────────────────────────────────────────────

  Timer? _reconnectTimer;

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      await close();
      if (_isInitiator) {
        await connectAsInitiator();
      } else {
        await connectAsResponder();
      }
    });
  }

  Future<void> close() async {
    _reconnectTimer?.cancel();
    await endCall();
    await _dc?.close();
    await _pc?.close();
    _dc = null;
    _pc = null;
    _setState(PeerState.disconnected);
  }

  void _setState(PeerState s) {
    _state = s;
    onStateChange?.call(s);
  }
}

// ── Registry — one connection per contact ─────────────────────────────────────

class ConnectionRegistry {
  ConnectionRegistry._();
  static final instance = ConnectionRegistry._();
  final _pool = <String, P2PConnection>{};

  P2PConnection getOrCreate({
    required String contactId,
    required String peerPubKey,
    required String localPubKey,
  }) => _pool.putIfAbsent(
        contactId,
        () => P2PConnection(
          contactId: contactId,
          peerPubKey: peerPubKey,
          localPubKey: localPubKey,
        ),
      );

  P2PConnection? get(String contactId) => _pool[contactId];

  Future<void> closeAll() async {
    for (final c in _pool.values) await c.close();
    _pool.clear();
  }
}
