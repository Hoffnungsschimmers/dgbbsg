import 'dart:async';
import 'dart:io';

/// 速度测试结果。
class SpeedTestResult {
  final String ip;
  final int port;
  final double speedMBps;     // 下载速度 (MB/s)
  final int bytesDownloaded;  // 下载字节数
  final Duration duration;    // 耗时
  final String? error;        // 错误信息（null 表示成功）

  const SpeedTestResult({
    required this.ip,
    required this.port,
    required this.speedMBps,
    required this.bytesDownloaded,
    required this.duration,
    this.error,
  });

  bool get success => error == null;
}

/// 下载源配置。
class SpeedTestSource {
  final String name;
  final String url;
  const SpeedTestSource(this.name, this.url);
}

/// 内置下载源列表（与 CFData-WEB 一致）。
const List<SpeedTestSource> speedTestSources = [
  SpeedTestSource('Cloudflare', 'https://speed.cloudflare.com/__down?bytes=99999999'),
  SpeedTestSource('CM', 'https://cf.090227.xyz/__down?bytes=99999999'),
  SpeedTestSource('移动', 'https://speed.okl.abrdns.com'),
];

/// 下载速度测试器。
class SpeedTester {
  /// 测试单个 IP 的下载速度。
  ///
  /// 通过 [ip]:[port] 代理访问 [sourceUrl]，测量下载速度。
  /// 使用 Dio 的 stream 模式逐块接收，避免内存膨胀。
  static Future<SpeedTestResult> testSingle(
    String ip,
    int port, {
    required String sourceUrl,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // 解析源 URL，提取主机名和路径
    final uri = Uri.parse(sourceUrl);
    final hostname = uri.host;
    final scheme = (port == 443 || port == 2053 || port == 2083 ||
        port == 2087 || port == 2096 || port == 8443)
        ? 'https' : 'http';
    // 直连 CF IP:port，Host 头设为源站域名（与 CFData-WEB 一致）
    final requestUrl = '$scheme://$ip:$port${uri.path}${uri.query.isNotEmpty ? "?${uri.query}" : ""}';

    final client = HttpClient()
      ..connectionTimeout = timeout
      ..badCertificateCallback = (_, _, _) => true;

    // 直连 CF IP:port，设置 Host 为源站域名（与原项目 CFData-WEB 一致）
    client.findProxy = (uri) => 'DIRECT';

    try {
      final sw = Stopwatch()..start();
      int totalBytes = 0;

      final req = await client.openUrl('GET', Uri.parse(requestUrl))
          .timeout(timeout);
      req.headers.set('Host', hostname);
      req.headers.set('User-Agent', 'Mozilla/5.0');
      req.close();

      final resp = await req.done.timeout(timeout);

      // 逐块读取，限时 5 秒
      final data = await resp.fold<List<int>>(<int>[], (prev, chunk) {
        totalBytes += chunk.length;
        return prev;
      }).timeout(const Duration(seconds: 5));

      sw.stop();
      totalBytes = data.length;

      final seconds = sw.elapsedMilliseconds / 1000.0;
      final speedMBps = seconds > 0 ? (totalBytes / 1024 / 1024) / seconds : 0.0;

      if (totalBytes == 0) {
        return SpeedTestResult(
          ip: ip, port: port, speedMBps: 0, bytesDownloaded: 0,
          duration: sw.elapsed, error: '未收到数据',
        );
      }

      return SpeedTestResult(
        ip: ip,
        port: port,
        speedMBps: speedMBps,
        bytesDownloaded: totalBytes,
        duration: sw.elapsed,
      );
    } catch (e) {
      return SpeedTestResult(
        ip: ip,
        port: port,
        speedMBps: 0,
        bytesDownloaded: 0,
        duration: Duration.zero,
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 批量速度测试（并发控制）。
  ///
  /// 对 [targets] 中的每个 (ip, port) 进行速度测试，最多 [workers] 个并发。
  /// 返回按速度降序排列的结果列表。
  static Future<List<SpeedTestResult>> testBatch(
    List<(String, int)> targets, {
    required String sourceUrl,
    int workers = 5,
    Duration timeout = const Duration(seconds: 15),
    void Function(int done, int total, double bestSpeed)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <SpeedTestResult>[];
    var done = 0;
    double bestSpeed = 0;
    var cancelled = false;

    final semaphore = _Semaphore(workers);

    await Future.wait(targets.map((t) async {
      if (cancelled || (isCancelled != null && isCancelled())) {
        cancelled = true;
        semaphore.cancel();
        return;
      }
      await semaphore.acquire();
      try {
        if (cancelled || (isCancelled != null && isCancelled())) {
          cancelled = true;
          semaphore.cancel();
          return;
        }
        final result = await testSingle(
          t.$1,
          t.$2,
          sourceUrl: sourceUrl,
          timeout: timeout,
        );
        results.add(result);
        if (result.success && result.speedMBps > bestSpeed) {
          bestSpeed = result.speedMBps;
        }
        done++;
        onProgress?.call(done, targets.length, bestSpeed);
      } finally {
        semaphore.release();
      }
    }));

    // 按速度降序排列
    results.sort((a, b) => b.speedMBps.compareTo(a.speedMBps));
    return results;
  }
}

/// 简易信号量，限制并发连接数。支持 [cancel] 立即释放所有等待者。
class _Semaphore {
  int _count;
  final _queue = <Completer<void>>[];
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
      _queue.removeAt(0).complete();
    } else {
      _count++;
    }
  }

  /// 立即释放所有排队中的 acquire()，使其不再阻塞。
  void cancel() {
    _cancelled = true;
    while (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    }
  }
}
