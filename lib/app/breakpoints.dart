/// 响应式断点定义（dp）。
/// Material 3 推荐值：
///   compact:   < 600  （手机竖屏）
///   medium:    600-839 （平板竖屏 / 小尺寸横屏）
///   expanded:  ≥ 840  （桌面 / 平板横屏）
class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;
}

enum FormFactor { compact, medium, expanded }

FormFactor formFactorOf(double width) {
  if (width < Breakpoints.compact) return FormFactor.compact;
  if (width < Breakpoints.medium) return FormFactor.medium;
  return FormFactor.expanded;
}
