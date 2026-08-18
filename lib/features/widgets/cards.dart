import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// 卡片容器。[animate] 为 true 时带淡入上滑入场动画。
Widget card(BuildContext context, {required Widget child, EdgeInsets? padding, bool animate = false, Duration? delay}) {
  final t = AppThemeExt.of(context);
  final widget = Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.radius,
      border: Border.all(color: t.border),
    ),
    child: child,
  );
  if (!animate) return widget;
  return widget
      .animate(delay: delay)
      .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
      .slideY(begin: 0.04, end: 0, duration: Motion.staggerDur, curve: Motion.curveStandard);
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  const AppButton(this.label, {this.onPressed, this.primary = true, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: 18),
        if (icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}
