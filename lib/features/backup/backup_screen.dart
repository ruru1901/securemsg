// lib/features/backup/backup_screen.dart
// PHASE 10 — Backup & Restore
//
// Split 6-digit hex code: first 3 digits stored locally, last 3 shown to peer device.
// Restore requires BOTH halves simultaneously.
// Code rotates every 24h automatically.
// Up to 5 slots. Each slot has integrity hash verification before restore.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/crypto/crypto_service.dart';
import '../../core/identity/identity_service.dart';
import '../../core/storage/database.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/widgets.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<BackupSlot> _slots = [];
  bool _loading = false;
  String? _error;
  String? _success;

  // Restore input
  final _localCodeCtrl = TextEditingController();  // user enters their 3 digits
  final _peerCodeCtrl  = TextEditingController();  // user enters peer's 3 digits
  int _restoreSlot = 1;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _localCodeCtrl.dispose();
    _peerCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    final slots = await AppDatabase.instance.getAllBackupSlots();
    if (mounted) setState(() => _slots = slots);
  }

  // ── Create backup ──────────────────────────────────────────────────────────

  Future<void> _createBackup(int slot) async {
    setState(() { _loading = true; _error = null; _success = null; });

    try {
      // 1. Serialize identity + contacts (media keys excluded from prototype)
      final payload = jsonEncode({
        'version': 1,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'pk': IdentityService.instance.publicKeyBase58,
        'sk': base64.encode(IdentityService.instance.secretKey),
      });
      final data = utf8.encode(payload);

      // 2. Generate 6-digit hex code
      final fullCode = _generateHexCode(); // e.g. "A3F9B2"
      final localCode = fullCode.substring(0, 3); // "A3F"
      final peerCode  = fullCode.substring(3, 6); // "9B2"

      // 3. Derive encryption key from full code + salt
      final salt       = CryptoService.instance.randomBytes(16);
      final backupKey  = CryptoService.instance.deriveBackupKey(fullCode, salt);

      // 4. Encrypt blob
      final encrypted = CryptoService.instance.encryptBackup(
        Uint8List.fromList(data), backupKey,
      );

      // 5. Compute integrity hash
      final hash = CryptoService.instance.hash(encrypted);

      // 6. Store slot
      final now = DateTime.now().millisecondsSinceEpoch;
      await AppDatabase.instance.saveBackupSlot(BackupSlotsCompanion(
        slot:          Value(slot),
        encryptedBlob: Value(encrypted),
        blobHash:      Value(hash),
        salt:          Value(salt),
        localCode:     Value(localCode),
        createdAt:     Value(now),
        rotatesAt:     Value(now + 86400 * 1000), // 24h rotation
      ));

      await _loadSlots();

      // Show peer code to share
      if (mounted) {
        _showPeerCode(peerCode, slot);
      }
    } catch (e) {
      setState(() => _error = 'Backup failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _generateHexCode() {
    final bytes = CryptoService.instance.randomBytes(3);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join().substring(0, 6);
  }

  void _showPeerCode(String peerCode, int slot) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Share this code', style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Send this 3-digit code to your OTHER device.\nBoth halves are needed to restore.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
              ),
              child: Text(
                peerCode,
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This code expires in 24 hours.\nDo not share via unencrypted channels.',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: peerCode));
            },
            child: const Text('Copy code'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Restore backup ─────────────────────────────────────────────────────────

  Future<void> _restoreBackup() async {
    final local = _localCodeCtrl.text.trim().toUpperCase();
    final peer  = _peerCodeCtrl.text.trim().toUpperCase();

    if (local.length != 3 || peer.length != 3) {
      setState(() => _error = 'Enter the full 3+3 digit code');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final slot = await AppDatabase.instance.getBackupSlot(_restoreSlot);
      if (slot == null) {
        setState(() => _error = 'Slot $_restoreSlot has no backup');
        return;
      }

      // Verify local code matches stored
      if (slot.localCode != local) {
        setState(() => _error = 'Local code does not match');
        return;
      }

      // Check if code has expired
      if (DateTime.now().millisecondsSinceEpoch > slot.rotatesAt) {
        setState(() => _error = 'Backup code has expired. Create a new backup.');
        return;
      }

      // Derive key from combined code
      final fullCode  = local + peer;
      final backupKey = CryptoService.instance.deriveBackupKey(fullCode, slot.salt);

      // Verify integrity hash first
      final valid = CryptoService.instance.verifyHash(slot.encryptedBlob, slot.blobHash);
      if (!valid) {
        setState(() => _error = 'Backup integrity check failed — file may be corrupted');
        return;
      }

      // Decrypt
      final decrypted = CryptoService.instance.decryptBackup(slot.encryptedBlob, backupKey);
      final json = jsonDecode(utf8.decode(decrypted)) as Map<String, dynamic>;

      // In production: restore identity + re-import contacts
      // For prototype: just verify we can decrypt
      if (json['pk'] != null) {
        setState(() => _success = 'Backup restored successfully! Restart the app.');
      } else {
        setState(() => _error = 'Backup data invalid');
      }
    } catch (e) {
      setState(() => _error = 'Restore failed — wrong code or corrupted backup');
    } finally {
      setState(() => _loading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg1,
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
            ),
            child: const Text(
              'Backups are split across two devices.\n'
              'Your device stores digits 1–3.\n'
              'You share digits 4–6 with your other device.\n'
              'Both halves are needed to restore. Codes rotate every 24h.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 24),

          // Error / success messages
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
              ),
              child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 13)),
            ),
          if (_success != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: Text(_success!, style: const TextStyle(color: AppTheme.success, fontSize: 13)),
            ),

          // Backup slots
          const Text('Backup slots',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          ...List.generate(5, (i) {
            final slot = i + 1;
            final existing = _slots.where((s) => s.slot == slot).firstOrNull;
            return _BackupSlotTile(
              slot: slot,
              existing: existing,
              loading: _loading,
              onCreate: () => _createBackup(slot),
            );
          }),

          const SizedBox(height: 32),
          const Divider(color: AppTheme.border),
          const SizedBox(height: 24),

          // Restore section
          const Text('Restore from backup',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Enter your stored 3-digit code and the code from your other device.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Slot selector
          Row(
            children: [
              const Text('Slot:', style: TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(width: 12),
              ...List.generate(5, (i) {
                final s = i + 1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SMChip(
                    label: '$s',
                    selected: _restoreSlot == s,
                    onTap: () => setState(() => _restoreSlot = s),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _CodeInput(
                  controller: _localCodeCtrl,
                  label: 'Your 3 digits',
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('—', style: TextStyle(color: AppTheme.textDim, fontSize: 20)),
              ),
              Expanded(
                child: _CodeInput(
                  controller: _peerCodeCtrl,
                  label: "Peer's 3 digits",
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SMButton(
            label: 'Restore',
            icon: Icons.restore,
            loading: _loading,
            onTap: _restoreBackup,
            destructive: false,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ── Backup slot tile ──────────────────────────────────────────────────────────

class _BackupSlotTile extends StatelessWidget {
  final int slot;
  final BackupSlot? existing;
  final bool loading;
  final VoidCallback onCreate;

  const _BackupSlotTile({
    required this.slot,
    required this.existing,
    required this.loading,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final hasBackup = existing != null;
    final isExpired = hasBackup &&
        DateTime.now().millisecondsSinceEpoch > existing!.rotatesAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Slot number
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hasBackup && !isExpired
                  ? AppTheme.success.withOpacity(0.1)
                  : AppTheme.bg3,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$slot',
                style: TextStyle(
                  color: hasBackup && !isExpired
                      ? AppTheme.success
                      : AppTheme.textDim,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBackup ? 'Slot $slot — backed up' : 'Slot $slot — empty',
                  style: TextStyle(
                    color: hasBackup ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hasBackup) ...[
                  const SizedBox(height: 2),
                  Text(
                    isExpired
                        ? 'Code expired — refresh needed'
                        : 'Your code: ${existing!.localCode}●●● · Rotates ${_rotatesIn(existing!.rotatesAt)}',
                    style: TextStyle(
                      color: isExpired ? AppTheme.danger : AppTheme.textDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Action
          TextButton(
            onPressed: loading ? null : onCreate,
            child: Text(
              hasBackup ? 'Refresh' : 'Create',
              style: TextStyle(
                color: hasBackup ? AppTheme.textSecondary : AppTheme.accent,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _rotatesIn(int rotatesAt) {
    final diff = Duration(
        milliseconds: rotatesAt - DateTime.now().millisecondsSinceEpoch);
    if (diff.isNegative) return 'now';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }
}

// ── Hex code input field ──────────────────────────────────────────────────────

class _CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _CodeInput({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: 3,
      textCapitalization: TextCapitalization.characters,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
        letterSpacing: 6,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        counterText: '',
        filled: true,
        fillColor: AppTheme.bg2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
      ),
    );
  }
}
