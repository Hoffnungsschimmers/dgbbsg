import 'dart:async';
import 'dart:io';

/// HTTP TTFB (Time To First Byte) 探测。
///
/// 签名与 [measureLatency] 完全一致，可直接传入 [latencyProbeAll] 的 probe 参数。
/// 对每个 probe 发送 HTTP GET 到 /cdn-cgi/trace，测量到收到第一个字节的时间。
Future<(double?, double?, int)> measureHttpTtfb(
  String ip,
  int port,
  Duration timeout, {
  int probes = 1,
  bool Function()? isCancelled,
}) async {
  final latencies = <double>[];
  for (var i = 0; i < probes; i++) {
    if (isCancelled != null && isCancelled()) break;
    try {
      final client = HttpClient()
        ..connectionTimeout = timeout
        ..badCertificateCallback = (_, _, _) => true;
      final sw = Stopwatch()..start();
      final request = await client.getUrl(Uri.parse('http://$ip:$port/cdn-cgi/trace'));
      request.headers.set('Host', 'www.cloudflare.com');
      request.headers.set('User-Agent', 'cfnb-app');
      final response = await request.close().timeout(timeout);
      await response.first.timeout(timeout);
      sw.stop();
      latencies.add(sw.elapsedMilliseconds.toDouble());
      client.close(force: true);
    } on TimeoutException {
      // 超时跳过
    } on SocketException {
      // 连接失败跳过
    } on IOException {
      // IO 错误跳过
    } catch (_) {
      // 其他错误跳过
    }
  }
  if (latencies.isEmpty) return (null, null, 0);
  final min = latencies.reduce((a, b) => a < b ? a : b);
  final jitter = latencies.length >= 2 ? _stdDev(latencies) : 0.0;
  return (min, jitter, latencies.length);
}

double _stdDev(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sumSq = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
  final variance = sumSq / values.length;
  return variance.isNaN ? 0.0 : _sqrt(variance);
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double guess = x / 2;
  for (var i = 0; i < 20; i++) {
    guess = (guess + x / guess) / 2;
  }
  return guess;
}
