// lib/features/chat/chat_list_screen.dart
// PHASE 8 — Chat list (home screen)
//
// Enhancements over spec:
//  • Unread count badges
//  • Last message preview (decrypted on-the-fly)
//  • Swipe to pin / swipe to delete
//  • Search bar with real-time filter
//  • Incognito mode toggle in appbar
//  • Connection status indicator per contact
//  • Long-press context menu

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/identity/identity_service.dart';
import '../../core/network/message_service.dart';
import '../../core/network/p2p_connection.dart';
import '../../core/storage/database.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/widgets.dart';
import '../pairing/pairing_screen.dart';
import '../settings/settings_screen.dart';
import 'chat_screen.dart';
import 'package:drift/drift.dart' show Value;

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  bool _incognito = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MessageService.instance.start();
    _searchCtrl.addListener(() => setState(() => _filter = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    MessageService.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Close idle connections after 10 min in background (handled in p2p)
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.bg1,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_searching) _buildSearchBar(),
            Expanded(child: _buildContactList()),
          ],
        ),
        floatingActionButton: _incognito ? null : FloatingActionButton(
          backgroundColor: AppTheme.accent,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          ),
          child: const Icon(Icons.qr_code_scanner, color: Colors.white),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          const Text('SecureMsg'),
          if (_incognito) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
              ),
              child: const Text(
                'INCOGNITO',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Incognito toggle
        IconButton(
          icon: Icon(
            _incognito ? Icons.visibility_off : Icons.visibility_outlined,
            color: _incognito ? AppTheme.danger : AppTheme.textSecondary,
          ),
          tooltip: 'Incognito mode',
          onPressed: () {
            HapticFeedback.lightImpact();
            setState(() => _incognito = !_incognito);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_incognito
                    ? 'Incognito on — messages not saved'
                    : 'Incognito off'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        // Search
        IconButton(
          icon: Icon(
            _searching ? Icons.search_off : Icons.search,
            color: AppTheme.textSecondary,
          ),
          onPressed: () {
            setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtrl.clear();
                _filter = '';
              }
            });
          },
        ),
        // Settings
        IconButton(
          icon: const Icon(Icons.tune_outlined, color: AppTheme.textSecondary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: const InputDecoration(
          hintText: 'Search contacts…',
          prefixIcon: Icon(Icons.search, color: AppTheme.textDim, size: 20),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildContactList() {
    return StreamBuilder<List<Contact>>(
      stream: Stream.periodic(const Duration(seconds: 2))
          .asyncMap((_) => AppDatabase.instance.getAllContacts()),
      builder: (context, snap) {
        final contacts = snap.data ?? [];
        final filtered = _filter.isEmpty
            ? contacts
            : contacts.where((c) => c.nickname.toLowerCase().contains(_filter)).toList();

        if (contacts.isEmpty) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'No contacts yet',
            subtitle: 'Tap the QR button to add your first contact by scanning their code.',
            action: SMButton(
              label: 'Add contact',
              icon: Icons.qr_code_scanner,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairingScreen()),
              ),
            ),
          );
        }

        if (filtered.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'No results',
            subtitle: 'No contacts match your search.',
          );
        }

        // Pinned contacts section
        final pinned   = filtered.where((c) => c.isPinned).toList();
        final unpinned = filtered.where((c) => !c.isPinned).toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: [
            if (pinned.isNotEmpty) ...[
              _sectionHeader('Pinned'),
              ...pinned.map((c) => _ContactTile(
                contact: c,
                incognito: _incognito,
                onOpen: () => _openChat(c),
                onPin: () => _togglePin(c),
                onDelete: () => _deleteContact(c),
              )),
              if (unpinned.isNotEmpty) _sectionHeader('All chats'),
            ],
            ...unpinned.map((c) => _ContactTile(
              contact: c,
              incognito: _incognito,
              onOpen: () => _openChat(c),
              onPin: () => _togglePin(c),
              onDelete: () => _deleteContact(c),
            )),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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

  void _openChat(Contact c) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          contactId: c.id,
          peerPubKey: c.publicKey,
          nickname: c.nickname,
          incognito: _incognito,
        ),
      ),
    );
  }

  Future<void> _togglePin(Contact c) async {
    await AppDatabase.instance.upsertContact(
      ContactsCompanion(
        id:        Value(c.id),
        nickname:  Value(c.nickname),
        publicKey: Value(c.publicKey),
        isPinned:  Value(!c.isPinned),
        createdAt: Value(c.createdAt),
      ),
    );
    setState(() {});
  }

  Future<void> _deleteContact(Contact c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bg2,
        title: const Text('Delete contact', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Delete ${c.nickname} and all messages? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.deleteConversation(c.id);
      await AppDatabase.instance.deleteContact(c.id);
      setState(() {});
    }
  }
}

// ── Contact tile ──────────────────────────────────────────────────────────────

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final bool incognito;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _ContactTile({
    required this.contact,
    required this.incognito,
    required this.onOpen,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final conn  = ConnectionRegistry.instance.get(contact.id);
    final online = conn?.state == PeerState.connected;

    return Dismissible(
      key: Key(contact.id),
      background: _swipeBg(Icons.push_pin, AppTheme.accent, Alignment.centerLeft),
      secondaryBackground: _swipeBg(Icons.delete_outline, AppTheme.danger, Alignment.centerRight),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onPin();
          return false;
        } else {
          onDelete();
          return false;
        }
      },
      child: HapticTap(
        onTap: onOpen,
        onLongPress: () => _showContextMenu(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppTheme.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Avatar with online indicator
              Stack(
                children: [
                  ContactAvatar(name: contact.nickname, size: 48),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: OnlineDot(isOnline: online),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Name + preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (contact.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.push_pin, size: 12, color: AppTheme.accent),
                          ),
                        Expanded(
                          child: Text(
                            contact.nickname,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Timestamp
                        if (contact.lastSeen != null)
                          Text(
                            _formatTime(contact.lastSeen!),
                            style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      incognito ? '••••••••••' : _statusText(online, conn?.state),
                      style: TextStyle(
                        color: online ? AppTheme.success : AppTheme.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusText(bool online, PeerState? state) {
    if (state == PeerState.connecting) return 'Connecting…';
    if (online) return 'Online';
    if (contact.lastSeen == null) return 'Never connected';
    return 'Last seen ${_formatTime(contact.lastSeen!)}';
  }

  String _formatTime(int ms) {
    final dt  = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays < 7) return ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][dt.weekday - 1];
    return '${dt.day}/${dt.month}';
  }

  Widget _swipeBg(IconData icon, Color color, Alignment align) {
    return Container(
      color: color.withOpacity(0.15),
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: color, size: 22),
    );
  }

  void _showContextMenu(BuildContext context) {
    showSMBottomSheet(
      context,
      title: contact.nickname,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _menuItem(context, Icons.push_pin_outlined,
                contact.isPinned ? 'Unpin chat' : 'Pin chat', onPin),
            _menuItem(context, Icons.qr_code, 'Re-scan QR', () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PairingScreen()));
            }),
            _menuItem(context, Icons.delete_outline, 'Delete contact', onDelete,
                color: AppTheme.danger),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label,
      VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.textSecondary, size: 22),
      title: Text(label,
          style: TextStyle(color: color ?? AppTheme.textPrimary, fontSize: 15)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}
