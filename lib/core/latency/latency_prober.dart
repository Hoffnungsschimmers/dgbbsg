import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' show sqrt;

/// 解析 `IP:端口#CC 来源` 节点行，返回 (ip, port)。
/// 支持 IPv4、[IPv6]:port、裸 IPv6:port 三种格式。
(IpPort, int)? parseEndpoint(String node) {
  // 取 # 之前的部分（ip:port 部分）
  final base = node.split('#').first.trim();
  if (base.isEmpty) return null;

  String ip;
  String portStr;
  if (base.startsWith('[')) {
    // IPv6 方括号格式: [2001:db8::1]:443
    final closeBracket = base.indexOf(']');
    if (closeBracket < 0) return null;
    ip = base.substring(1, closeBracket);
    // ] 后应跟 :port
    if (closeBracket + 1 >= base.length || base[closeBracket + 1] != ':') return null;
    portStr = base.substring(closeBracket + 2);
  } else {
    final idx = base.lastIndexOf(':');
    if (idx < 0) return null;
    ip = base.substring(0, idx);
    portStr = base.substring(idx + 1);
    // 区分 IPv4:port 与 IPv6:port：IPv6 地址含多个冒号
    if (ip.contains(':')) {
      // 裸 IPv6:port — 验证 IPv6 格式（至少含 2 个冒号）
      if (!ip.contains('::') && ip.split(':').length < 3) return null;
    }
  }
  final port = int.tryParse(portStr.trim());
  if (port == null || port <= 0 || port > 65535) return null;
  return (ip, port);
}

typedef IpPort = String;

/// 测量到 (ip, port) 的 TCP 连接延迟（毫秒）。
///
/// 串行 [probes] 次连接，返回 (最小延迟, 抖动标准差, 成功次数)。
/// 抖动越小表示节点越稳定。一次都没成功时返回 (null, null, 0)。
/// [isCancelled] 非空时，每次探测前/后检查，中途中断。
Future<(double?, double?, int)> measureLatency(
  String ip,
  int port,
  Duration timeout, {
  int probes = 1,
  bool Function()? isCancelled,
}) async {
  final latencies = <double>[];
  for (var i = 0; i < probes; i++) {
    if (isCancelled != null && isCancelled()) break;
    final sw = Stopwatch()..start();
    Socket? sock;
    try {
      sock = await Socket.connect(ip, port, timeout: timeout);
      latencies.add(sw.elapsedMilliseconds.toDouble());
    } on SocketException {
      // 本次失败，继续
    } on TimeoutException {
      // 本次超时，继续
    } finally {
      try { await sock?.close(); } catch (_) {}
    }
  }
  if (latencies.isEmpty) return (null, null, 0);
  final min = latencies.reduce((a, b) => a < b ? a : b);
  final jitter = latencies.length >= 2 ? _stdDev(latencies) : 0.0;
  return (min, jitter, latencies.length);
}

/// 计算标准差（√方差）。
double _stdDev(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sumSq = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
  final variance = sumSq / values.length;
  return variance.isNaN ? 0.0 : sqrt(variance);
}

/// 在 `#` 后的字符串中定位国家码与来源之间的分隔符位置。
///
/// 兼容新格式 `#HK CM`（空格分隔）和旧格式 `#HK@CM`（@ 分隔）。
/// 返回第一个出现的空格或 @ 的索引，均不存在时返回 -1。
int findCcSourceSep(String afterHash) {
  final spaceIdx = afterHash.indexOf(' ');
  final atIdx = afterHash.indexOf('@');
  if (spaceIdx >= 0 && (atIdx < 0 || spaceIdx < atIdx)) return spaceIdx;
  if (atIdx >= 0) return atIdx;
  return -1;
}

/// 提取节点注释里的国家码（# 之后、来源之前）。
/// 兼容新格式 `#HK CM` 和旧格式 `#HK@CM`。
String nodeCountry(String node) {
  final hashIdx = node.indexOf('#');
  if (hashIdx < 0) return '';
  final afterHash = node.substring(hashIdx + 1);
  final sepIdx = findCcSourceSep(afterHash);
  return afterHash.substring(0, sepIdx >= 0 ? sepIdx : afterHash.length).trim();
}

/// 延迟测试结果。
class LatencyResult {
  final String node;
  final double? latencyMs;
  final double? jitterMs; // 抖动（标准差），越小越稳定
  final int successCount;
  LatencyResult(this.node, this.latencyMs, [this.jitterMs, this.successCount = 0]);
}

/// 对节点列表做并发延迟测试。
///
/// 对应旧版 tester.py 的 run_tcp_tests_async：每个节点测 [probes] 次，
/// 成功率 (< [minSuccessRate]) 的节点被丢弃（与旧版 min_success_rate 一致）。
/// 返回按 (-successCount, latency) 排序的结果，以及测试/连通计数。
Future<(List<LatencyResult>, int tested, int connected)> latencyProbeAll(
  List<String> nodes, {
  required Duration timeout,
  required int workers,
  int probes = 1,
  double minSuccessRate = 1.0,
  int? earlyStopCount,
  double maxLatency = 0,
  Map<String, String>? nodeSource,
  Future<(double?, double?, int)> Function(String ip, int port, Duration timeout, {int probes, bool Function()? isCancelled})? probe,
  void Function(String)? onLog,
  /// 取消检查：返回 true 时跳过后续节点探测。
  bool Function()? isCancelled,
  /// 节点完成回调：每完成一个节点探测即时触发（不节流），
  /// 携带 (done=已探测, total=总节点数, connected=已连通) 供 UI 进度条精确刷新。
  void Function(int done, int total, int connected)? onProgress,
  /// 单个结果回调：每完成一个达标探测即时触发，供 UI 实时显示结果。
  void Function(LatencyResult result)? onResult,
}) async {
  final logBuf = <String>[];
  Timer? flushTimer;
  void flushLog() {
    if (logBuf.isEmpty) return;
    final batch = logBuf.join('\n');
    logBuf.clear();
    onLog?.call(batch);
  }

  void scheduleLogFlush() {
    flushTimer ??= Timer(const Duration(milliseconds: 120), () {
      flushTimer = null;
      flushLog();
      if (logBuf.isNotEmpty) scheduleLogFlush();
    });
  }

  final targets = <(String, IpPort, int)>[];
  var parseFailed = 0;
  for (final node in nodes) {
    final ep = parseEndpoint(node);
    if (ep != null) {
      targets.add((node, ep.$1, ep.$2));
    } else {
      parseFailed++;
    }
  }

  if (targets.isEmpty) {
    onLog?.call('警告：${nodes.length} 行数据中无有效节点格式（期望 ip:port#CC）。'
        '${parseFailed > 0 ? " $parseFailed 行解析失败。" : ""}');
    return (<LatencyResult>[], nodes.length, 0);
  }
  if (parseFailed > 0) {
    onLog?.call('提示：$parseFailed 行无法解析为 ip:port 格式，已跳过。');
  }

  final results = <LatencyResult>[];
  final semaphore = _Semaphore(workers);
  var done = 0;
  var connected = 0;
  var qualified = 0; // 连通 + 满足成功率 + 延迟 ≤ maxLatency 的节点数
  var stopped = false;

  bool shouldStop() {
    if (stopped) return true;
    if (isCancelled != null && isCancelled()) return true;
    if (earlyStopCount != null && qualified >= earlyStopCount) return true;
    return false;
  }

  await Future.wait(targets.map((t) async {
    if (shouldStop()) {
      stopped = true;
      semaphore.cancel();
      return;
    }
    await semaphore.acquire();
    try {
      // 先计数，再探测，跳过也计数
      done++;
      onProgress?.call(done, targets.length, connected);
      if (shouldStop()) {
        stopped = true;
        semaphore.cancel();
        return;
      }
      final (lat, jitter, ok) = await (probe ?? measureLatency)(
        t.$2, t.$3, timeout,
        probes: probes,
        isCancelled: shouldStop,
      );
      if (shouldStop()) {
        stopped = true;
        semaphore.cancel();
        return;
      }
      final rate = probes > 0 ? ok / probes : 0.0;
      final okLat = (lat != null && rate >= minSuccessRate);
      if (okLat) {
        final result = LatencyResult(t.$1, lat, jitter, ok);
        results.add(result);
        connected++;
        // 只有延迟也达标才算 qualified
        if (maxLatency <= 0 || lat <= maxLatency) {
          qualified++;
          onResult?.call(result);
        }
      } else {
        results.add(LatencyResult(t.$1, null, null, ok));
      }
      // 达标数够结果限制就停止
      if (earlyStopCount != null && qualified >= earlyStopCount) {
        stopped = true;
        semaphore.cancel();
        onLog?.call('达标 $qualified 个（延迟≤${maxLatency.round()}ms），达到结果限制 $earlyStopCount，停止扫描。');
      }
      final ep = '${t.$2}:${t.$3}';
      final line = okLat
          ? '  [$done/${targets.length}] $ep  ${lat.toStringAsFixed(1)} ms'
          : '  [$done/${targets.length}] $ep  超时/失败';
      logBuf.add(line);
      scheduleLogFlush();
    } finally {
      semaphore.release();
    }
  }));
  flushLog();

  final succeeded = results.where((r) => r.latencyMs != null).toList()
    ..sort((a, b) {
      final sc = b.successCount.compareTo(a.successCount);
      if (sc != 0) return sc;
      return a.latencyMs!.compareTo(b.latencyMs!);
    });
  final failed = results.where((r) => r.latencyMs == null).toList();
  final ordered = [...succeeded, ...failed];

  return (ordered, targets.length, succeeded.length);
}

/// 简易信号量，限制并发连接数。支持 [cancel] 立即释放所有等待者。
class _Semaphore {
  int _count;
  final _queue = ListQueue<Completer<void>>();
  bool _cancelled = false;
  _Semaphore(this._count);

  Future<void> acquire() async {
    if (_cancelled) return;
    if (_count > 0) {
      _count--;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _count++;
    }
  }

  /// 立即释放所有排队中的 acquire()，使其不再阻塞。
  void cancel() {
    _cancelled = true;
    while (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    }
  }
}
