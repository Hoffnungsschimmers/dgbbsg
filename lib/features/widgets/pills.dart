import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// 状态药丸。根据背景色亮度自动选择文字颜色。
/// 使用 [AnimatedSwitcher] 实现内容变化时的淡入淡出过渡。
Widget pill(BuildContext context, String text, Color bg) {
  final fg = _contrastColor(bg, context);
  return AnimatedSwitcher(
    duration: Motion.durFast,
    switchInCurve: Motion.curveStandard,
    switchOutCurve: Motion.curveExit,
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: anim, child: child),
    ),
    child: Container(
      key: ValueKey('$text-${bg.value}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
    ),
  );
}

/// 带图标的药丸（emoji/time 等场景替换为 Icon）。
Widget pillWithIcon(BuildContext context, {required IconData icon, required String text, required Color bg}) {
  final fg = _contrastColor(bg, context);
  return AnimatedSwitcher(
    duration: Motion.durFast,
    switchInCurve: Motion.curveStandard,
    switchOutCurve: Motion.curveExit,
    transitionBuilder: (child, anim) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: anim, child: child),
    ),
    child: Container(
      key: ValueKey('$icon-$text-${bg.value}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    ),
  );
}

/// 根据背景色亮度返回白色或主题正文色。
Color _contrastColor(Color bg, BuildContext context) {
  // 计算相对亮度（WCAG 公式）
  final luminance = bg.computeLuminance();
  return luminance > 0.4 ? AppThemeExt.of(context).text : Colors.white;
}
