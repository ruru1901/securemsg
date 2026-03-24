// lib/features/settings/settings_screen.dart
// PHASE 11 — Settings
//
// All privacy + performance controls in one place:
//  • WiFi-only media transfers
//  • Default disappearing message timer
//  • Screenshot protection toggle
//  • Incognito mode default
//  • Identity (view public key, copy, QR)
//  • Backup shortcut
//  • Connection diagnostics
//  • About + open source notices

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/identity/identity_service.dart';
import '../../core/network/p2p_connection.dart';
import '../../core/network/signaling_service.dart';
import '../../core/storage/database.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/widgets.dart';
import '../backup/backup_screen.dart';
import '../pairing/pairing_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Settings state (in production: persist to SharedPreferences)
  bool _wifiOnlyMedia      = true;
  bool _screenshotProtect  = true;
  bool _defaultIncognito   = false;
  int? _defaultDisappear;  // seconds, null = off
  bool _showDiag           = false;

  static const _disappearOptions = [
    (label: 'Off',  seconds: null),
    (label: '1 min', seconds: 60),
    (label: '1 hour', seconds: 3600),
    (label: '1 day', seconds: 86400),
    (label: '1 week', seconds: 604800),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg1,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ── Identity section ──────────────────────────────────────────────
          _sectionHeader('My identity'),
          _IdentityCard(),

          // ── Privacy section ───────────────────────────────────────────────
          _sectionHeader('Privacy'),
          _SwitchTile(
            icon: Icons.screenshot_monitor_outlined,
            title: 'Screenshot protection',
            subtitle: 'Blocks screenshots (Android only)',
            value: _screenshotProtect,
            onChanged: (v) => setState(() => _screenshotProtect = v),
          ),
          _SwitchTile(
            icon: Icons.visibility_off_outlined,
            title: 'Default incognito',
            subtitle: 'New chats start without message storage',
            value: _defaultIncognito,
            onChanged: (v) => setState(() => _defaultIncognito = v),
          ),
          _TapTile(
            icon: Icons.timer_outlined,
            title: 'Default disappearing timer',
            subtitle: _defaultDisappear == null
                ? 'Off'
                : _disappearOptions
                    .firstWhere((o) => o.seconds == _defaultDisappear,
                        orElse: () => (label: 'Custom', seconds: _defaultDisappear))
                    .label,
            onTap: () => _pickDisappearTimer(),
          ),

          // ── Data section ──────────────────────────────────────────────────
          _sectionHeader('Data & performance'),
          _SwitchTile(
            icon: Icons.wifi_outlined,
            title: 'WiFi-only media',
            subtitle: 'Only transfer media on WiFi',
            value: _wifiOnlyMedia,
            onChanged: (v) => setState(() => _wifiOnlyMedia = v),
          ),
          _TapTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear all messages',
            subtitle: 'Permanently delete all conversations',
            danger: true,
            onTap: _confirmClearAll,
          ),

          // ── Backup section ────────────────────────────────────────────────
          _sectionHeader('Backup'),
          _TapTile(
            icon: Icons.backup_outlined,
            title: 'Backup & Restore',
            subtitle: 'Encrypted split-code backup',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            ),
          ),

          // ── Connections section ───────────────────────────────────────────
          _sectionHeader('Connections'),
          _TapTile(
            icon: Icons.qr_code_outlined,
            title: 'Add contact',
            subtitle: 'Scan or show QR code',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PairingScreen()),
            ),
          ),
          _TapTile(
            icon: Icons.network_check_outlined,
            title: 'Connection diagnostics',
            subtitle: 'View server status and active peers',
            onTap: () => setState(() => _showDiag = !_showDiag),
          ),
          if (_showDiag) _DiagnosticsPanel(),

          // ── About section ─────────────────────────────────────────────────
          _sectionHeader('About'),
          _TapTile(
            icon: Icons.info_outline,
            title: 'SecureMsg',
            subtitle: 'Version 1.0.0 · Open source · Zero data collected',
            onTap: () {},
          ),
          _TapTile(
            icon: Icons.lock_outline,
            title: 'Security model',
            subtitle: 'Curve25519 + XSalsa20-Poly1305 · libsodium',
            onTap: () => _showSecurityInfo(),
          ),
          _TapTile(
            icon: Icons.warning_amber_outlined,
            title: 'Privacy limitations',
            subtitle: 'What we cannot protect against',
            onTap: () => _showPrivacyLimits(),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.textDim,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Future<void> _pickDisappearTimer() async {
    showSMBottomSheet(
      context,
      title: 'Default disappearing timer',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: _disappearOptions.map((opt) {
            return ListTile(
              title: Text(opt.label,
                  style: const TextStyle(color: AppTheme.textPrimary)),
              trailing: _defaultDisappear == opt.seconds
                  ? const Icon(Icons.check, color: AppTheme.accent)
                  : null,
              onTap: () {
                setState(() => _defaultDisappear = opt.seconds);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Clear all messages',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This permanently deletes all messages and media from this device. Contacts are kept. This cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final contacts = await AppDatabase.instance.getAllContacts();
      for (final c in contacts) {
        await AppDatabase.instance.deleteConversation(c.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All messages deleted')),
        );
      }
    }
  }

  void _showSecurityInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Security model', style: TextStyle(color: AppTheme.textPrimary)),
        content: const SingleChildScrollView(
          child: Text(
            '• Identity: Curve25519 keypair (libsodium)\n'
            '• Messages: crypto_box_easy (XSalsa20-Poly1305)\n'
            '• Media: crypto_secretbox per-file key\n'
            '• Backup: Argon2id key derivation\n'
            '• Transport: DTLS-SRTP (WebRTC built-in)\n'
            '• Storage: SQLCipher AES-256\n\n'
            'No forward secrecy in v1. Planned for v2 via X3DH.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.7, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyLimits() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Privacy limitations', style: TextStyle(color: AppTheme.textPrimary)),
        content: const SingleChildScrollView(
          child: Text(
            '• Signaling relay sees your public key and connection timestamps (not message content)\n\n'
            '• STUN server sees both IP addresses briefly during connection setup\n\n'
            '• TURN relay sees encrypted bytes if used as fallback\n\n'
            '• Screenshot protection is enforced on Android only — iOS can only log attempts\n\n'
            '• No forwarding is a UI restriction only — text can be copied manually\n\n'
            '• Disappearing messages delete locally only — peer\'s device retains copy until their timer fires\n\n'
            '• Your public key is a persistent identifier to anyone you pair with',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.7, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Identity card ─────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pubKey = IdentityService.instance.publicKeyBase58;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ContactAvatar(name: IdentityService.instance.publicKeyShort, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your identity',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    Text(IdentityService.instance.publicKeyShort,
                        style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Full public key:',
            style: TextStyle(color: AppTheme.textDim, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            pubKey,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pubKey));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Public key copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: const Text('Copy key'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PairingScreen()),
                  ),
                  icon: const Icon(Icons.qr_code, size: 16),
                  label: const Text('Show QR'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accentDim),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Diagnostics panel ─────────────────────────────────────────────────────────

class _DiagnosticsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _diagRow('Signaling server', SignalingService.instance.isConnected ? '✓ Connected' : '✗ Disconnected',
              SignalingService.instance.isConnected),
          _diagRow('Active P2P connections',
              ConnectionRegistry.instance.toString(), true),
          const SizedBox(height: 8),
          const Text('STUN: stun.l.google.com:19302',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11, fontFamily: 'monospace')),
          const Text('TURN: metered.ca + cloudflare + openrelay (random)',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ),
          Text(
            value,
            style: TextStyle(
              color: ok ? AppTheme.success : AppTheme.danger,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable setting tiles ────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 22),
      title: Text(title, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
        inactiveTrackColor: AppTheme.bg3,
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  const _TapTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.danger : AppTheme.textSecondary;
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(title,
          style: TextStyle(
              color: danger ? AppTheme.danger : AppTheme.textPrimary,
              fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: AppTheme.textDim, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textDim, size: 18),
      onTap: onTap,
    );
  }
}
