import 'dart:async';

/// 指数退避重试：失败时依次 sleep `initialDelay * 2^attempt`，单次 sleep
/// 上限 60 秒。最终失败则 [rethrow] 原始异常。
///
/// [sleep] 默认为 `Future.delayed`；测试可注入 mock 以跳过真实睡眠。
/// [onRetry] 每次重试前回调，用于日志输出。
///
/// `maxRetries=2` 表示「最多额外重试 2 次」（共 3 次尝试）。
/// `maxRetries=0` 表示不重试（只走第一次）。
Future<T> retry<T>(
  Future<T> Function() body, {
  required int maxRetries,
  required Duration initialDelay,
  Future<void> Function(Duration)? sleep,
  void Function(int attempt, int maxRetries, Object error, Duration delay)? onRetry,
}) async {
  final sleeper = sleep ?? Future.delayed;
  var attempt = 0;
  while (true) {
    try {
      return await body();
    } catch (e) {
      if (attempt >= maxRetries) rethrow;
      var d = initialDelay * (1 << attempt);
      if (d > const Duration(seconds: 60)) d = const Duration(seconds: 60);
      onRetry?.call(attempt + 1, maxRetries, e, d);
      await sleeper(d);
      attempt++;
    }
  }
}
