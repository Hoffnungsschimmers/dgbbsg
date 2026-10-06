/// Shared by automatic and manual push; unknown evidence never counts as a
/// measured POP. Defaults are product safeguards, not a accuracy guarantee.
String? pushQualityIssue({
  required int nodes,
  required int totalIps,
  required int measured,
  required int estimated,
  int previousNodes = 0,
  int minimumNodes = 1,
  double minimumMeasuredRatio = 0.5,
  double minimumRetainedRatio = 0.5,
}) {
  if (minimumNodes < 1 || !minimumMeasuredRatio.isFinite ||
      minimumMeasuredRatio < 0 || minimumMeasuredRatio > 1 ||
      !minimumRetainedRatio.isFinite || minimumRetainedRatio < 0 || minimumRetainedRatio > 1) {
    return '推送保护配置无效，请检查节点数量和比例';
  }
  if (nodes < minimumNodes) return '有效节点 $nodes 个，低于最低数量 $minimumNodes';
  if (totalIps <= 0) return '没有本轮落地检测证据，请先执行测落地';
  if (measured / totalIps < minimumMeasuredRatio) {
    return 'POP 实测 $measured/$totalIps，低于 ${(minimumMeasuredRatio * 100).round()}% 门槛'
        '（归属地估算 $estimated 个不计入实测）';
  }
  if (previousNodes > 0 && nodes / previousNodes < minimumRetainedRatio) {
    return '节点由 $previousNodes 减少到 $nodes，低于上次的 ${(minimumRetainedRatio * 100).round()}%';
  }
  return null;
}
