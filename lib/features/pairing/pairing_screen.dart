// lib/features/pairing/pairing_screen.dart
// PHASE 7 — QR Pairing
//
// Two modes:
//   SHOW: displays own QR code for peer to scan
//   SCAN: opens camera to scan peer's QR code
//
// QR payload: { v:1, pk:"base58pubkey", ts:unixms }
// After scan: creates contact, initiates WebRTC connection

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/identity/identity_service.dart';
import '../../core/network/p2p_connection.dart';
import '../../core/storage/database.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/widgets.dart';
import '../chat/chat_screen.dart';

const _uuid = Uuid();

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _scanController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _scanning = true;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 1) {
        _scanController.start();
      } else {
        _scanController.stop();
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _scanController.dispose();
    super.dispose();
  }

  // ── QR payload ─────────────────────────────────────────────────────────────

  String get _qrPayload => jsonEncode({
        'v': 1,
        'pk': IdentityService.instance.publicKeyBase58,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

  // ── Handle scan ────────────────────────────────────────────────────────────

  Future<void> _onScan(BarcodeCapture capture) async {
    if (!_scanning || _connecting) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    setState(() {
      _scanning = false;
      _connecting = true;
      _error = null;
    });

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['v'] != 1) throw Exception('Unknown QR version');

      final peerPubKey = data['pk'] as String;
      final myPubKey   = IdentityService.instance.publicKeyBase58;

      if (peerPubKey == myPubKey) {
        throw Exception("That's your own QR code");
      }

      // Check if contact already exists
      final existing = await AppDatabase.instance.getContactByPubKey(peerPubKey);
      String contactId;

      if (existing != null) {
        contactId = existing.id;
      } else {
        // Create new contact with auto-generated nickname
        contactId = _uuid.v4();
        final shortKey = '${peerPubKey.substring(0, 6)}…${peerPubKey.substring(peerPubKey.length - 4)}';
        await AppDatabase.instance.upsertContact(ContactsCompanion(
          id:        Value(contactId),
          nickname:  Value('User $shortKey'),
          publicKey: Value(peerPubKey),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ));
      }

      // Initiate P2P connection
      final conn = ConnectionRegistry.instance.getOrCreate(
        contactId: contactId,
        peerPubKey: peerPubKey,
        localPubKey: myPubKey,
      );
      conn.connectAsInitiator();

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      // Navigate to chat with this contact
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            contactId: contactId,
            peerPubKey: peerPubKey,
            nickname: existing?.nickname ?? 'New contact',
          ),
        ),
      );
    } catch (e) {
      setState(() {
        _connecting = false;
        _scanning = true;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg1,
      appBar: AppBar(
        title: const Text('Add contact'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'My QR code'),
            Tab(text: 'Scan code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildShowQR(),
          _buildScanQR(),
        ],
      ),
    );
  }

  Widget _buildShowQR() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Let the other person scan this',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          // QR card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: _qrPayload,
              version: QrVersions.auto,
              size: 240,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Public key display
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.key_outlined, size: 16, color: AppTheme.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    IdentityService.instance.publicKeyBase58,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  color: AppTheme.textDim,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: IdentityService.instance.publicKeyBase58,
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Public key copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your identity is this key pair.\nNo account, no phone number, no email.',
            style: TextStyle(
              color: AppTheme.textDim,
              fontSize: 12,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildScanQR() {
    return Stack(
      children: [
        // Camera
        ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: MobileScanner(
            controller: _scanController,
            onDetect: _onScan,
          ),
        ),

        // Overlay frame
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: _error != null ? AppTheme.danger : AppTheme.accent,
                width: 2.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Connecting overlay
        if (_connecting)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppTheme.accent),
                  SizedBox(height: 16),
                  Text(
                    'Connecting…',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),

        // Error message
        if (_error != null)
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _error = null),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ),

        // Hint
        if (!_connecting)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Point at the other person\'s QR code',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
