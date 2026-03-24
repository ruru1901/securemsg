// lib/shared/widgets/widgets.dart
// Reusable UI components used across features

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ── Avatar widget ─────────────────────────────────────────────────────────────

class ContactAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;

  const ContactAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join();

    final bgColor = color ?? _colorFromName(name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  static Color _colorFromName(String name) {
    final colors = [
      const Color(0xFF4F8EF7),
      const Color(0xFF7C5CBF),
      const Color(0xFF2ECC71),
      const Color(0xFFE74C3C),
      const Color(0xFFE67E22),
      const Color(0xFF1ABC9C),
      const Color(0xFF9B59B6),
      const Color(0xFF3498DB),
    ];
    if (name.isEmpty) return colors[0];
    final idx = name.codeUnitAt(0) % colors.length;
    return colors[idx];
  }
}

// ── Online indicator dot ──────────────────────────────────────────────────────

class OnlineDot extends StatelessWidget {
  final bool isOnline;
  final double size;

  const OnlineDot({super.key, required this.isOnline, this.size = 10});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isOnline ? AppTheme.success : AppTheme.textDim,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.bg1, width: 1.5),
      ),
    );
  }
}

// ── Message state ticks ───────────────────────────────────────────────────────

class MessageTicks extends StatelessWidget {
  final int state; // 0=sending, 1=sent, 2=delivered, 3=seen

  const MessageTicks({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == 0) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppTheme.textDim,
        ),
      );
    }

    final color = state == 3 ? AppTheme.accent : AppTheme.textDim;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 14, color: color),
        if (state >= 2)
          Transform.translate(
            offset: const Offset(-6, 0),
            child: Icon(Icons.check, size: 14, color: color),
          ),
      ],
    );
  }
}

// ── Disappearing timer badge ──────────────────────────────────────────────────

class DisappearBadge extends StatelessWidget {
  final int seconds;

  const DisappearBadge({super.key, required this.seconds});

  String get _label {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 11, color: AppTheme.danger),
          const SizedBox(width: 3),
          Text(
            _label,
            style: const TextStyle(
              color: AppTheme.danger,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pill chip ─────────────────────────────────────────────────────────────────

class SMChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const SMChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.18) : AppTheme.bg2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet helper ───────────────────────────────────────────────────────

Future<T?> showSMBottomSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppTheme.bg2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            child,
          ],
        ),
      ),
    ),
  );
}

// ── Haptic tap wrapper ────────────────────────────────────────────────────────

class HapticTap extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const HapticTap({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      onLongPress: onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              onLongPress!();
            }
          : null,
      child: child,
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.textDim),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Primary button ────────────────────────────────────────────────────────────

class SMButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool destructive;
  final IconData? icon;

  const SMButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.destructive = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.danger : AppTheme.accent;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
