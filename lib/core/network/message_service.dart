// lib/core/network/message_service.dart
// PHASE 6 — Messaging
//
// Handles the full message lifecycle:
//   send → encrypt → try P2P → fallback to outbox queue
//   receive → decrypt → store → send ACK
//   outbox drain → retry with backoff on reconnect
//   disappearing messages → background purge job
//
// Wire frame format: [ type(1) | payload(n) ]
// type 0x01 = text message JSON
// type 0x02 = delivery ACK
// type 0x03 = seen ACK
// type 0x04 = media chunk (handled by MediaService)
// type 0x05 = ping/keepalive

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import '../crypto/crypto_service.dart';
import '../identity/identity_service.dart';
import '../storage/database.dart';
import 'p2p_connection.dart';

const _uuid = Uuid();

// ── Wire types ────────────────────────────────────────────────────────────────
const kTypeText     = 0x01;
const kTypeDelivery = 0x02;
const kTypeSeen     = 0x03;
const kTypeMedia    = 0x04;
const kTypePing     = 0x05;

// Message state constants (mirrors DB)
const kStateSending   = 0;
const kStateSent      = 1;
const kStateDelivered = 2;
const kStateSeen      = 3;

// Retry backoff steps in seconds
const _retryBackoff = [1, 2, 5, 15, 60, 120, 300];

class MessageService {
  MessageService._();
  static final instance = MessageService._();

  final _db     = AppDatabase.instance;
  final _crypto = CryptoService.instance;
  final _id     = IdentityService.instance;

  Timer? _purgeTimer;
  Timer? _drainTimer;

  // ── Init ──────────────────────────────────────────────────────────────────

  void start() {
    // Purge expired messages every 60 seconds
    _purgeTimer = Timer.periodic(const Duration(seconds: 60), (_) => _purgeExpired());
    // Attempt outbox drain every 10 seconds
    _drainTimer = Timer.periodic(const Duration(seconds: 10), (_) => _drainOutbox());
  }

  void stop() {
    _purgeTimer?.cancel();
    _drainTimer?.cancel();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  /// Send a text message to [contactId].
  /// Returns the message ID immediately; delivery is async.
  Future<String> sendText({
    required String contactId,
    required String peerPubKey,
    required String text,
    String? replyToId,
    int? disappearAfterSeconds,
  }) async {
    final msgId = _uuid.v4();
    final now   = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = disappearAfterSeconds != null
        ? now + disappearAfterSeconds * 1000
        : null;

    // Build plaintext payload
    final payload = jsonEncode({
      'id':        msgId,
      'body':      text,
      'ts':        now,
      'replyToId': replyToId,
    });

    // Encrypt
    final peerPk  = IdentityService.fromBase58(peerPubKey);
    final cipher  = _crypto.encryptMessage(payload, peerPk);
    final nonce   = cipher.sublist(0, 24);
    final ctBytes = cipher.sublist(24);

    // Persist locally (state=sending)
    await _db.insertMessage(MessagesCompanion(
      id:         Value(msgId),
      contactId:  Value(contactId),
      isOutgoing: const Value(true),
      ciphertext: Value(ctBytes),
      nonce:      Value(nonce),
      timestamp:  Value(now),
      state:      const Value(kStateSending),
      replyToId:  Value(replyToId),
      expiresAt:  Value(expiresAt),
    ));

    // Build wire frame: [ 0x01 | nonce(24) | ciphertext ]
    final frame = Uint8List.fromList([kTypeText, ...cipher]);

    // Try P2P send
    final conn = ConnectionRegistry.instance.get(contactId);
    final sent = conn != null ? await conn.send(frame) : false;

    if (sent) {
      await _db.updateMessageState(msgId, kStateSent);
    } else {
      // Queue for later
      await _db.enqueue(OutboxQueueCompanion(
        id:          Value(_uuid.v4()),
        contactId:   Value(contactId),
        frame:       Value(frame),
        createdAt:   Value(now),
        nextRetryAt: Value(now + 1000),
      ));
    }

    return msgId;
  }

  // ── Receive ───────────────────────────────────────────────────────────────

  /// Call this when raw bytes arrive from the data channel.
  Future<void> onFrame(Uint8List raw, {
    required String contactId,
    required String peerPubKey,
  }) async {
    if (raw.isEmpty) return;
    final type    = raw[0];
    final payload = raw.sublist(1);

    switch (type) {
      case kTypeText:
        await _handleIncomingText(payload, contactId: contactId, peerPubKey: peerPubKey);
        break;
      case kTypeDelivery:
        final msgId = utf8.decode(payload);
        await _db.updateMessageState(msgId, kStateDelivered);
        break;
      case kTypeSeen:
        final msgId = utf8.decode(payload);
        await _db.updateMessageState(msgId, kStateSeen);
        break;
      case kTypePing:
        // ignore
        break;
    }
  }

  Future<void> _handleIncomingText(Uint8List cipher, {
    required String contactId,
    required String peerPubKey,
  }) async {
    final peerPk = IdentityService.fromBase58(peerPubKey);
    final plain  = _crypto.decryptMessage(cipher, peerPk);
    final json   = jsonDecode(plain) as Map<String, dynamic>;

    final msgId = json['id'] as String;
    final now   = DateTime.now().millisecondsSinceEpoch;
    final nonce = cipher.sublist(0, 24);
    final ct    = cipher.sublist(24);

    await _db.insertMessage(MessagesCompanion(
      id:         Value(msgId),
      contactId:  Value(contactId),
      isOutgoing: const Value(false),
      ciphertext: Value(ct),
      nonce:      Value(nonce),
      timestamp:  Value(json['ts'] as int? ?? now),
      state:      const Value(kStateDelivered),
      replyToId:  Value(json['replyToId'] as String?),
    ));

    // Send delivery ACK back
    final conn = ConnectionRegistry.instance.get(contactId);
    final ack  = Uint8List.fromList([kTypeDelivery, ...utf8.encode(msgId)]);
    await conn?.send(ack);
  }

  // ── Mark seen ─────────────────────────────────────────────────────────────

  Future<void> markSeen(String msgId, {
    required String contactId,
    required String peerPubKey,
  }) async {
    await _db.updateMessageState(msgId, kStateSeen);
    final conn = ConnectionRegistry.instance.get(contactId);
    final ack  = Uint8List.fromList([kTypeSeen, ...utf8.encode(msgId)]);
    await conn?.send(ack);
  }

  // ── Outbox drain ──────────────────────────────────────────────────────────

  Future<void> _drainOutbox() async {
    final contacts = await _db.getAllContacts();
    for (final contact in contacts) {
      final conn = ConnectionRegistry.instance.get(contact.id);
      if (conn == null || !conn.canSend) continue;

      final pending = await _db.getPendingOutbox(contact.id);
      final now     = DateTime.now().millisecondsSinceEpoch;

      for (final item in pending) {
        if (item.nextRetryAt > now) continue;

        final sent = await conn.send(item.frame);
        if (sent) {
          await _db.dequeue(item.id);
          // Find the message this frame belongs to and mark sent
          // (In full impl: embed msgId in frame header for easy lookup)
        } else {
          final retries   = item.retryCount.clamp(0, _retryBackoff.length - 1);
          final nextRetry = now + _retryBackoff[retries] * 1000;
          await _db.bumpRetry(item.id, nextRetryAt: nextRetry);
        }
      }
    }
  }

  // ── Expiry purge ──────────────────────────────────────────────────────────

  Future<void> _purgeExpired() => _db.purgeExpiredMessages();

  // ── Decrypt for display ───────────────────────────────────────────────────

  /// Decrypt a stored message for display in the UI.
  String? decryptForDisplay(Message msg, String peerPubKey) {
    try {
      final cipher = Uint8List.fromList([...msg.nonce, ...msg.ciphertext]);
      final peerPk = IdentityService.fromBase58(peerPubKey);
      if (msg.isOutgoing) {
        // We encrypted it — decrypt with our own sk + peer pk
        return _crypto.decryptMessage(cipher, peerPk);
      } else {
        return _crypto.decryptMessage(cipher, peerPk);
      }
    } catch (_) {
      return null; // decryption failure — corrupted or wrong key
    }
  }
}
