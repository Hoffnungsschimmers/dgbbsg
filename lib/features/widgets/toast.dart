import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// 轻量应用内 Toast（OverlayEntry + 动画）。
/// 使用：AppToast.show(context, '消息', success: true);
class AppToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    bool success = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    _current?.remove();
    _current = null;

    final t = AppThemeExt.of(context);
    final bg = success ? t.success : t.danger;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        bg: bg,
        icon: icon,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
        duration: duration,
      ),
    );
    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Color bg;
  final IconData icon;
  final VoidCallback onDismiss;
  final Duration duration;
  const _ToastWidget({
    required this.message,
    required this.bg,
    required this.icon,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  late Animation<double> _scale;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Motion.durBase);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard);
    _offset = Tween(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard));
    _scale = Tween(begin: 0.92, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    // 进场动画
    _ctrl.forward();
    // 自动消失
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _dismiss() {
    if (!mounted) return;
    _ctrl.duration = Motion.durFast;
    _ctrl.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏（NavigationRail）时用固定底部偏移，窄屏（NavigationBar）时加上导航栏高度
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final bottom = viewPadding.bottom + (isWide ? 16.0 : kBottomNavigationBarHeight + 8);
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: _dismiss,
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _offset,
            child: ScaleTransition(
              scale: _scale,
              child: Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: widget.bg,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: widget.bg.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.icon, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
