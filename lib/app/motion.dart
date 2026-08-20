import 'package:flutter/animation.dart';

/// 动效令牌系统：集中所有时长 / 曲线 / 过渡，杜绝散落魔法数。
/// 设计意图：保持单一来源，UI 层只引用 [Motion.x]，便于全局调参与一致性。
class Motion {
  Motion._();

  /// 时长档位（毫秒概念，转 Duration）。
  static const Duration durFast = Duration(milliseconds: 150);
  static const Duration durBase = Duration(milliseconds: 250);
  static const Duration durSlow = Duration(milliseconds: 400);
  static const Duration durPage = Duration(milliseconds: 500);

  /// 主题切换过渡时长（亮度变色用）。
  static const Duration durTheme = Duration(milliseconds: 450);

  /// 节流刷新间隔（进度回调 → UI flush，约 60Hz 余量）。
  static const Duration throttleTick = Duration(milliseconds: 60);

  /// 去抖保存间隔（ConfigTab 输入 → 落盘）。
  static const Duration saveDebounce = Duration(milliseconds: 300);

  /// 曲线档位。
  /// - [curveEmphasized]：强调进出场（页面/卡片）。
  /// - [curveStandard]：常规反馈（按钮/数字）。
  /// - [curveExit]：退场收尾。
  static const Curve curveEmphasized = Cubic(0.2, 0.0, 0.0, 1.0); // easeInOutCubicEmphasized 近似
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;

  /// 列表错峰入场：第 i 项的相对延迟（按索引递增，封顶 6 项避免长列表超时）。
  static Duration staggerDelay(int i, {Duration step = const Duration(milliseconds: 40)}) {
    final clamped = i.clamp(0, 6);
    return step * clamped;
  }

  /// 错峰时基础时长（含 delay 后的可见动画）。
  static const Duration staggerDur = Duration(milliseconds: 300);
}
