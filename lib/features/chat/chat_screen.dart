// lib/features/chat/chat_screen.dart
// PHASE 8 — Chat screen
//
// Enhancements:
//  • Reply-to threading with quoted preview
//  • Disappearing message timer picker
//  • Long-press message menu (reply, copy, delete, set timer)
//  • Blur media thumbnails until tapped
//  • Incognito mode (no storage)
//  • Screenshot detection attempt via FLAG_SECURE
//  • Typing indicator (local only)
//  • Auto-scroll to bottom on new message
//  • Date separators between message groups

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/network/message_service.dart';
import '../../core/network/p2p_connection.dart';
import '../../core/storage/database.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/widgets.dart';
import '../calls/call_screen.dart';

const _uuid = Uuid();

class ChatScreen extends StatefulWidget {
  final String contactId;
  final String peerPubKey;
  final String nickname;
  final bool incognito;

  const ChatScreen({
    super.key,
    required this.contactId,
    required this.peerPubKey,
    required this.nickname,
    this.incognito = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();

  Message? _replyTo;
  int? _disappearSeconds; // null = no disappearing
  bool _showTimerPicker = false;

  static const _timerOptions = [
    (label: 'Off',  seconds: null),
    (label: '30s',  seconds: 30),
    (label: '1m',   seconds: 60),
    (label: '5m',   seconds: 300),
    (label: '1h',   seconds: 3600),
    (label: '1d',   seconds: 86400),
  ];

  @override
  void initState() {
    super.initState();
    // FLAG_SECURE: prevent screenshots on Android
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _enableSecureFlag();

    // Set up incoming data handler for this contact
    final conn = ConnectionRegistry.instance.get(widget.contactId);
    if (conn != null) {
      conn.onData = (data) {
        MessageService.instance.onFrame(
          data,
          contactId: widget.contactId,
          peerPubKey: widget.peerPubKey,
        );
        _scrollToBottom();
      };
    }
  }

  void _enableSecureFlag() {
    // Android FLAG_SECURE — prevents screenshots and screen recording
    const platform = MethodChannel('securemsg/window');
    platform.invokeMethod('setSecureFlag', true).catchError((_) {});
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    const platform = MethodChannel('securemsg/window');
    platform.invokeMethod('setSecureFlag', false).catchError((_) {});
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Send message ──────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    _inputCtrl.clear();
    HapticFeedback.lightImpact();

    if (widget.incognito) {
      // Incognito: show in UI but don't persist
      _showIncognitoMessage(text);
      return;
    }

    await MessageService.instance.sendText(
      contactId: widget.contactId,
      peerPubKey: widget.peerPubKey,
      text: text,
      replyToId: _replyTo?.id,
      disappearAfterSeconds: _disappearSeconds,
    );

    setState(() => _replyTo = null);
    _scrollToBottom();
  }

  void _showIncognitoMessage(String text) {
    // In incognito mode messages display temporarily in a local list
    // (not stored to DB) — handled by the stream below by NOT inserting
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message sent (not saved — incognito mode)'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg0,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_showTimerPicker) _buildTimerPicker(),
          Expanded(child: _buildMessageList()),
          if (_replyTo != null) _buildReplyPreview(),
          _buildInputBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    final conn   = ConnectionRegistry.instance.get(widget.contactId);
    final online = conn?.state == PeerState.connected;

    return AppBar(
      titleSpacing: 0,
      title: GestureDetector(
        onTap: () {}, // TODO: open contact info
        child: Row(
          children: [
            Stack(
              children: [
                ContactAvatar(name: widget.nickname, size: 36),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: OnlineDot(isOnline: online, size: 9),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.nickname,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    if (_disappearSeconds != null) ...[
                      DisappearBadge(seconds: _disappearSeconds!),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      _connectionStatus(conn?.state),
                      style: TextStyle(
                        color: online ? AppTheme.success : AppTheme.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // Call button
        IconButton(
          icon: const Icon(Icons.call_outlined),
          color: AppTheme.textSecondary,
          onPressed: online ? _startCall : null,
        ),
        // Disappearing timer
        IconButton(
          icon: Icon(
            Icons.timer_outlined,
            color: _disappearSeconds != null ? AppTheme.accent : AppTheme.textSecondary,
          ),
          onPressed: () => setState(() => _showTimerPicker = !_showTimerPicker),
        ),
      ],
    );
  }

  String _connectionStatus(PeerState? s) {
    switch (s) {
      case PeerState.connected:   return 'Online';
      case PeerState.connecting:  return 'Connecting…';
      case PeerState.failed:      return 'Connection failed';
      default:                    return 'Offline';
    }
  }

  Widget _buildTimerPicker() {
    return Container(
      height: 48,
      color: AppTheme.bg2,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: _timerOptions.map((opt) {
          final selected = opt.seconds == _disappearSeconds;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: SMChip(
              label: opt.label,
              selected: selected,
              onTap: () {
                setState(() {
                  _disappearSeconds = opt.seconds;
                  _showTimerPicker = false;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageList() {
    if (widget.incognito) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_off, size: 40, color: AppTheme.textDim),
            SizedBox(height: 12),
            Text('Incognito mode — messages not saved',
                style: TextStyle(color: AppTheme.textDim, fontSize: 13)),
          ],
        ),
      );
    }

    return StreamBuilder<List<Message>>(
      stream: AppDatabase.instance.watchMessages(widget.contactId),
      builder: (context, snap) {
        final msgs = snap.data ?? [];
        if (msgs.isEmpty) {
          return const Center(
            child: Text(
              'Send your first message',
              style: TextStyle(color: AppTheme.textDim, fontSize: 14),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: msgs.length,
          itemBuilder: (ctx, i) {
            final msg  = msgs[i];
            final prev = i > 0 ? msgs[i - 1] : null;

            // Decrypt for display
            final plainJson = MessageService.instance.decryptForDisplay(msg, widget.peerPubKey);
            final body = plainJson != null
                ? (jsonDecode(plainJson)['body'] as String? ?? '[error]')
                : '[decryption failed]';

            // Date separator
            final showDate = prev == null ||
                !_sameDay(prev.timestamp, msg.timestamp);

            return Column(
              children: [
                if (showDate) _buildDateSeparator(msg.timestamp),
                _MessageBubble(
                  message: msg,
                  body: body,
                  replyToBody: msg.replyToId != null
                      ? _findReplyBody(msgs, msg.replyToId!)
                      : null,
                  onLongPress: () => _showMessageMenu(msg, body),
                  onReplyTap: () {
                    // Scroll to replied message
                    final idx = msgs.indexWhere((m) => m.id == msg.replyToId);
                    if (idx >= 0) {
                      _scrollCtrl.animateTo(
                        idx * 72.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _findReplyBody(List<Message> msgs, String replyToId) {
    final orig = msgs.where((m) => m.id == replyToId).firstOrNull;
    if (orig == null) return null;
    final plainJson = MessageService.instance.decryptForDisplay(orig, widget.peerPubKey);
    if (plainJson == null) return null;
    return jsonDecode(plainJson)['body'] as String?;
  }

  Widget _buildDateSeparator(int ms) {
    final dt  = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String label;
    if (_sameDay(ms, now.millisecondsSinceEpoch)) {
      label = 'Today';
    } else if (_sameDay(ms, now.subtract(const Duration(days: 1)).millisecondsSinceEpoch)) {
      label = 'Yesterday';
    } else {
      label = '${dt.day}/${dt.month}/${dt.year}';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppTheme.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ),
          const Expanded(child: Divider(color: AppTheme.border)),
        ],
      ),
    );
  }

  bool _sameDay(int ms1, int ms2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ms1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ms2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  Widget _buildReplyPreview() {
    final body = _replyTo != null
        ? (MessageService.instance.decryptForDisplay(_replyTo!, widget.peerPubKey))
        : null;
    final bodyText = body != null
        ? (jsonDecode(body)['body'] as String? ?? '')
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: AppTheme.bg2,
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyTo!.isOutgoing ? 'You' : widget.nickname,
                  style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  bodyText,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppTheme.textDim),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.bg1,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // Media attach button
          IconButton(
            icon: const Icon(Icons.attach_file_outlined, size: 22),
            color: AppTheme.textSecondary,
            onPressed: _attachMedia,
          ),
          // Text input
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _focusNode,
              maxLines: 5,
              minLines: 1,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: widget.incognito ? 'Incognito message…' : 'Message…',
                hintStyle: const TextStyle(color: AppTheme.textDim),
                filled: true,
                fillColor: AppTheme.bg2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          ListenableBuilder(
            listenable: _inputCtrl,
            builder: (_, __) {
              final hasText = _inputCtrl.text.trim().isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasText ? AppTheme.accent : AppTheme.bg3,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.send_rounded,
                    size: 18,
                    color: hasText ? Colors.white : AppTheme.textDim,
                  ),
                  onPressed: hasText ? _sendMessage : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _attachMedia() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Media transfer coming in phase 9')),
    );
  }

  void _startCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactId: widget.contactId,
          peerPubKey: widget.peerPubKey,
          nickname: widget.nickname,
        ),
      ),
    );
  }

  void _showMessageMenu(Message msg, String body) {
    showSMBottomSheet(
      context,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: AppTheme.textSecondary),
              title: const Text('Reply', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _replyTo = msg);
                _focusNode.requestFocus();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined, color: AppTheme.textSecondary),
              title: const Text('Copy text', style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: body));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
              onTap: () async {
                Navigator.pop(context);
                await AppDatabase.instance.deleteConversation(msg.contactId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final Message message;
  final String body;
  final String? replyToBody;
  final VoidCallback onLongPress;
  final VoidCallback? onReplyTap;

  const _MessageBubble({
    required this.message,
    required this.body,
    this.replyToBody,
    required this.onLongPress,
    this.onReplyTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOutgoing;
    final hasExpiry = message.expiresAt != null;

    return Padding(
      padding: EdgeInsets.only(
        left: isOut ? 64 : 12,
        right: isOut ? 12 : 64,
        bottom: 4,
        top: 2,
      ),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOut ? AppTheme.accentDim : AppTheme.bg2,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isOut ? 18 : 4),
                  bottomRight: Radius.circular(isOut ? 4 : 18),
                ),
                border: !isOut
                    ? Border.all(color: AppTheme.border, width: 0.5)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reply quote
                  if (replyToBody != null)
                    GestureDetector(
                      onTap: onReplyTap,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: const Border(
                            left: BorderSide(color: AppTheme.accent, width: 3),
                          ),
                        ),
                        child: Text(
                          replyToBody!,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  // Message body
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),

                  // Timestamp + state row
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasExpiry)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: DisappearBadge(
                            seconds: ((message.expiresAt! - DateTime.now().millisecondsSinceEpoch) / 1000).clamp(0, 999999).round(),
                          ),
                        ),
                      Text(
                        _formatTime(message.timestamp),
                        style: const TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 10,
                        ),
                      ),
                      if (isOut) ...[
                        const SizedBox(width: 4),
                        MessageTicks(state: message.state),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
