import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/notification_helper.dart';
import '../../app/providers.dart';
import '../latency/latency_prober.dart';
import '../net/ip.dart';
import 'cf_range_scanner.dart';
import 'http_ping.dart';
import 'speed_test.dart';

/// 扫描模式：TCPing 或 HTTPing (TTFB)。
enum ScanMode {
  tcpPing('TCPing', 'TCP 握手延迟'),
  httpPing('HTTPing', 'HTTP 首字节时间');

  const ScanMode(this.label, this.description);
  final String label;
  final String description;
}

/// 扫描来源：官方 CF 段或自定义列表。
enum ScanSource {
  cfRange('官方 CF 段', '扫描 Cloudflare 已知 IP 地址段'),
  customList('自定义列表', '从文件或 URL 导入 IP 列表');

  const ScanSource(this.label, this.description);
  final String label;
  final String description;
}

/// 扫描进度。
class ScanProgress {
  final int done;
  final int total;
  final int connected;
  const ScanProgress({required this.done, required this.total, required this.connected});
  double get percent => total == 0 ? 0 : done / total;
}

/// 速度测试进度。
class SpeedProgress {
  final int done;
  final int total;
  final double bestSpeedMBps;
  const SpeedProgress({required this.done, required this.total, required this.bestSpeedMBps});
  double get percent => total == 0 ? 0 : done / total;
}

/// 数据中心分组（官方模式第一阶段结果）。
class DCGroup {
  final String dc;       // 数据中心代码，如 NRT、SIN
  final String country;  // 落地区域国家码
  final String city;     // 城市
  final int ipCount;     // 该 DC 下的 IP 数量
  final double minLatency; // 该 DC 下最低延迟
  const DCGroup({required this.dc, required this.country, required this.city, required this.ipCount, required this.minLatency});
}

/// 详细测试结果（官方模式第二阶段，每 IP 多轮探测）。
class DetailedResult {
  final String ip;
  final int port;
  final String dc;
  final String country;
  final String region;
  final String city;
  final double minLatency;
  final double maxLatency;
  final double avgLatency;
  final double lossRate;   // 0.0 ~ 1.0
  final int attempts;
  final int successCount;
  double? speedMBps;
  String speedText;        // "5.23MB/s" 或 "未测速" 或错误信息
  bool speedQualified;

  DetailedResult({
    required this.ip,
    required this.port,
    required this.dc,
    required this.country,
    required this.region,
    required this.city,
    required this.minLatency,
    required this.maxLatency,
    required this.avgLatency,
    required this.lossRate,
    required this.attempts,
    required this.successCount,
    this.speedMBps,
    this.speedText = '未测速',
    this.speedQualified = false,
  });
}

/// 扫描状态。
class ScannerState {
  final bool scanning;
  final bool speedTesting;
  final bool detailTesting;
  final ScanMode scanMode;
  final ScanSource scanSource;
  final List<LatencyResult> results;
  final List<SpeedTestResult> speedResults;
  final ScanProgress? progress;
  final SpeedProgress? speedProgress;

  // DC 分组相关（官方模式）
  final List<DCGroup> dcGroups;
  final String? selectedDC;
  final List<DetailedResult> detailedResults;

  final int? lastTested;
  final int? lastConnected;

  const ScannerState({
    this.scanning = false,
    this.speedTesting = false,
    this.detailTesting = false,
    this.scanMode = ScanMode.tcpPing,
    this.scanSource = ScanSource.cfRange,
    this.results = const [],
    this.speedResults = const [],
    this.progress,
    this.speedProgress,
    this.dcGroups = const [],
    this.selectedDC,
    this.detailedResults = const [],
    this.lastTested,
    this.lastConnected,
  });

  ScannerState copyWith({
    bool? scanning,
    bool? speedTesting,
    bool? detailTesting,
    ScanMode? scanMode,
    ScanSource? scanSource,
    List<LatencyResult>? results,
    List<SpeedTestResult>? speedResults,
    ScanProgress? progress,
    bool clearProgress = false,
    SpeedProgress? speedProgress,
    bool clearSpeedProgress = false,
    List<DCGroup>? dcGroups,
    String? selectedDC,
    bool clearSelectedDC = false,
    List<DetailedResult>? detailedResults,
    int? lastTested,
    int? lastConnected,
  }) =>
      ScannerState(
        scanning: scanning ?? this.scanning,
        speedTesting: speedTesting ?? this.speedTesting,
        detailTesting: detailTesting ?? this.detailTesting,
        scanMode: scanMode ?? this.scanMode,
        scanSource: scanSource ?? this.scanSource,
        results: results ?? this.results,
        speedResults: speedResults ?? this.speedResults,
        progress: clearProgress ? null : (progress ?? this.progress),
        speedProgress: clearSpeedProgress ? null : (speedProgress ?? this.speedProgress),
        dcGroups: dcGroups ?? this.dcGroups,
        selectedDC: clearSelectedDC ? null : (selectedDC ?? this.selectedDC),
        detailedResults: detailedResults ?? this.detailedResults,
        lastTested: lastTested ?? this.lastTested,
        lastConnected: lastConnected ?? this.lastConnected,
      );
}

/// 扫描通知器：管理延迟扫描和速度测试的生命周期。
class ScannerNotifier extends StateNotifier<ScannerState> {
  final Ref ref;
  bool _cancelRequested = false;

  ScannerNotifier(this.ref) : super(const ScannerState());

  /// 更新扫描模式。
  void setScanMode(ScanMode mode) {
    state = state.copyWith(scanMode: mode);
  }

  /// 更新扫描来源。
  void setScanSource(ScanSource source) {
    state = state.copyWith(scanSource: source);
  }

  /// 取消当前操作。
  void cancel() {
    _cancelRequested = true;
  }

  /// ═══════════════════════════════════════════════════════
  /// 官方模式：第一阶段 — 快速扫描 + DC 分组
  /// ═══════════════════════════════════════════════════════
  ///
  /// 扫描 CF IP 段，对每个通过的 IP 做 cdn-cgi/trace 检测数据中心，
  /// 按 DC 分组返回结果。每 IP 只做 1 次快速探测（非详细测试）。
  Future<void> runDCScan({
    required int port,
    required int workers,
    required Duration timeout,
    required double maxLatency,
    int? topN,
  }) async {
    if (state.scanning) return;
    _cancelRequested = false;
    state = state.copyWith(scanning: true, results: [], speedResults: [], dcGroups: [], clearSelectedDC: true, detailedResults: []);

    final logger = ref.read(subLoggerProvider);
    logger.info('开始官方优选扫描（DC 分组模式）');

    try {
      // 1. 生成 CF IP 列表
      final ips = await CfRangeScanner.generateIPs(onLog: (m) => logger.info(m));
      logger.info('标准优选：${ips.length} 个待测 IP');

      // 2. 构造节点行
      final nodes = ips.map((ip) => '$ip:$port').toList();

      // 3. 进度节流
      ScanProgress? latestProgress;
      Timer? progressTimer;
      void scheduleFlush() {
        progressTimer ??= Timer(Motion.throttleTick, () {
          progressTimer = null;
          if (latestProgress != null) {
            state = state.copyWith(progress: latestProgress);
          }
          if (latestProgress != null && latestProgress!.done < latestProgress!.total) {
            scheduleFlush();
          }
        });
      }

      // 4. 快速探测（1 次，不做多轮）
      logger.info('开始探测：${nodes.length} 个 IP，端口=$port');
      final liveResults = <LatencyResult>[];
      final (probeResults, tested, connected) = await latencyProbeAll(
        nodes,
        timeout: timeout,
        workers: workers,
        probes: 1,
        minSuccessRate: 0.0,
        maxLatency: maxLatency,
        probe: state.scanMode == ScanMode.httpPing ? measureHttpTtfb : measureLatency,
        onLog: (m) => logger.info(m),
        isCancelled: () => _cancelRequested,
        onProgress: (done, total, conn) {
          latestProgress = ScanProgress(done: done, total: total, connected: conn);
          scheduleFlush();
        },
        onResult: (r) {
          liveResults.add(r);
          final sorted = [...liveResults]..sort((a, b) => (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999));
          state = state.copyWith(results: sorted);
        },
      );

      progressTimer?.cancel();

      // 5. 过滤通过的 IP
      var passed = probeResults.where((r) =>
          r.latencyMs != null && (maxLatency <= 0 || r.latencyMs! <= maxLatency)).toList();
      passed.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
      if (topN != null && topN > 0 && passed.length > topN) {
        passed = passed.sublist(0, topN);
      }

      // 6. 对通过的 IP 做 cdn-cgi/trace 地理定位 + DC 检测
      logger.info('正在通过 cdn-cgi/trace 检测 ${passed.length} 个 IP 的数据中心…');
      final geoMap = <String, String>{}; // ip -> country code
      for (var i = 0; i < passed.length; i++) {
        if (_cancelRequested) break;
        final r = passed[i];
        final ep = parseEndpoint(r.node);
        if (ep == null) continue;
        final ip = ep.$1;
        if (isCloudflareIp(ip)) {
          final cc = await geolocateCfIp(ip);
          if (cc.isNotEmpty) {
            geoMap[ip] = cc;
            passed[i] = LatencyResult('$ip:${ep.$2}#$cc', r.latencyMs, r.jitterMs, r.successCount);
          }
        }
      }

      // 7. 按 DC 分组
      final dcEntries = <String, List<LatencyResult>>{};
      for (final r in passed) {
        final ep = parseEndpoint(r.node);
        if (ep == null) continue;
        final cc = geoMap[ep.$1] ?? nodeCountry(r.node);
        final dc = _countryToDC(cc);
        dcEntries.putIfAbsent(dc, () => []).add(r);
      }
      final dcGroups = <DCGroup>[];
      for (final entry in dcEntries.entries) {
        final dc = entry.key;
        final group = entry.value;
        final minLat = group.map((r) => r.latencyMs ?? 99999).reduce((a, b) => a < b ? a : b);
        final cc = group.isNotEmpty ? (geoMap[parseEndpoint(group[0].node)?.$1 ?? ''] ?? nodeCountry(group[0].node)) : '';
        dcGroups.add(DCGroup(
          dc: dc,
          country: cc,
          city: '',
          ipCount: group.length,
          minLatency: minLat,
        ));
      }
      dcGroups.sort((a, b) => a.minLatency.compareTo(b.minLatency));

      if (_cancelRequested) {
        logger.info('扫描已取消（已完成 $tested 个探测）');
      } else {
        logger.info('扫描完成：测试 $tested / 连通 $connected / 通过 ${passed.length} / DC ${dcGroups.length} 个');
      }

      state = state.copyWith(
        scanning: false,
        clearProgress: true,
        results: passed,
        dcGroups: dcGroups,
        lastTested: tested,
        lastConnected: connected,
      );

      NotificationHelper.taskComplete(
        taskName: '官方优选扫描完成',
        summary: '测试 $tested / 连通 $connected / 通过 ${passed.length} / DC ${dcGroups.length} 个',
      );
    } catch (e) {
      logger.error('扫描失败：$e');
      state = state.copyWith(scanning: false, clearProgress: true);
      NotificationHelper.taskFailed(taskName: '扫描', error: e.toString());
    }
  }

  /// 从国家码推断数据中心代码。
  String _countryToDC(String cc) {
    const map = {
      'JP': 'NRT', 'SG': 'SIN', 'US': 'LAX', 'HK': 'HKG', 'TW': 'TPE',
      'KR': 'ICN', 'CN': 'PVG', 'DE': 'FRA', 'GB': 'LHR', 'FR': 'CDG',
      'AU': 'SYD', 'IN': 'BOM', 'BR': 'GRU', 'RU': 'SVO', 'NL': 'AMS',
      'CA': 'YYZ', 'IT': 'MXP', 'SE': 'ARN', 'PL': 'WAW', 'ID': 'CGK',
      'TH': 'BKK', 'MY': 'KUL', 'PH': 'MNL', 'VN': 'SGN',
    };
    return map[cc] ?? cc;
  }

  /// ═══════════════════════════════════════════════════════
  /// 官方模式：第二阶段 — 选 DC 详细测试
  /// ═══════════════════════════════════════════════════════
  ///
  /// 对选中 DC 下的所有 IP 做多轮延迟探测，输出 min/max/avg/丢包率。
  Future<void> runDetailedTest(String dc, {int attempts = 10}) async {
    if (state.detailTesting) return;
    _cancelRequested = false;
    state = state.copyWith(detailTesting: true, selectedDC: dc, detailedResults: []);

    final logger = ref.read(subLoggerProvider);
    logger.info('开始详细测试 DC=$dc，每个 IP 测 $attempts 次');

    try {
      // 1. 筛选该 DC 下的 IP
      final dcResults = state.results.where((r) {
        final ep = parseEndpoint(r.node);
        if (ep == null) return false;
        final cc = nodeCountry(r.node);
        return _countryToDC(cc) == dc;
      }).toList();

      if (dcResults.isEmpty) {
        logger.warning('DC=$dc 下无可用 IP');
        state = state.copyWith(detailTesting: false);
        return;
      }

      logger.info('DC=$dc 共 ${dcResults.length} 个 IP 待详细测试');

      // 2. 逐 IP 多轮探测（并发控制）
      final detailed = <DetailedResult>[];
      var done = 0;

      // 进度节流
      ScanProgress? latestProgress;
      Timer? progressTimer;
      void scheduleFlush() {
        progressTimer ??= Timer(Motion.throttleTick, () {
          progressTimer = null;
          if (latestProgress != null) {
            state = state.copyWith(progress: latestProgress);
          }
          if (latestProgress != null && latestProgress!.done < latestProgress!.total) {
            scheduleFlush();
          }
        });
      }

      final probe = state.scanMode == ScanMode.httpPing ? measureHttpTtfb : measureLatency;

      for (final r in dcResults) {
        if (_cancelRequested) break;
        final ep = parseEndpoint(r.node);
        if (ep == null) continue;
        final ip = ep.$1;
        final p = ep.$2;
        final cc = nodeCountry(r.node);

        final (minLat, jitter, ok) = await probe(ip, p, const Duration(seconds: 3),
            probes: attempts, isCancelled: () => _cancelRequested);

        done++;
        latestProgress = ScanProgress(done: done, total: dcResults.length, connected: detailed.where((d) => d.successCount > 0).length);
        scheduleFlush();

        if (minLat == null || ok == 0) {
          detailed.add(DetailedResult(
            ip: ip, port: p, dc: dc, country: cc, region: '', city: '',
            minLatency: 0, maxLatency: 0, avgLatency: 0, lossRate: 1.0,
            attempts: attempts, successCount: 0,
          ));
          continue;
        }

        // jitter = 标准差，用于估算 max/avg
        // avg ≈ min + jitter（近似），max ≈ min + 2*jitter（近似）
        final avg = minLat + (jitter ?? 0) * 0.5;
        final max = minLat + (jitter ?? 0) * 2.0;
        final lossRate = (attempts - ok) / attempts;

        detailed.add(DetailedResult(
          ip: ip, port: p, dc: dc, country: cc, region: '', city: '',
          minLatency: minLat, maxLatency: max, avgLatency: avg,
          lossRate: lossRate, attempts: attempts, successCount: ok,
        ));
      }

      progressTimer?.cancel();

      // 按 minLatency 排序
      detailed.sort((a, b) => a.minLatency.compareTo(b.minLatency));

      if (_cancelRequested) {
        logger.info('详细测试已取消');
      } else {
        logger.info('详细测试完成：${detailed.length} 个 IP，${detailed.where((d) => d.successCount > 0).length} 个连通');
      }

      state = state.copyWith(
        detailTesting: false,
        clearProgress: true,
        detailedResults: detailed,
      );
    } catch (e) {
      logger.error('详细测试失败：$e');
      state = state.copyWith(detailTesting: false, clearProgress: true);
    }
  }

  /// ═══════════════════════════════════════════════════════
  /// 单 IP 测速（逐行测速按钮调用）
  /// ═══════════════════════════════════════════════════════
  Future<void> runSingleSpeedTest(String ip, int port, {required String sourceUrl, required double minSpeedMBps}) async {
    final logger = ref.read(subLoggerProvider);
    logger.info('开始对 $ip:$port 测速…');

    final result = await SpeedTester.testSingle(ip, port, sourceUrl: sourceUrl);

    if (result.success) {
      final speedText = '${result.speedMBps.toStringAsFixed(2)}MB/s';
      logger.info('$ip 测速完成：$speedText');

      // 更新 detailedResults 中对应 IP 的速度
      final updated = state.detailedResults.map((d) {
        if (d.ip == ip && d.port == port) {
          d.speedMBps = result.speedMBps;
          d.speedText = speedText;
          d.speedQualified = result.speedMBps >= minSpeedMBps;
        }
        return d;
      }).toList();

      // 同时更新 speedResults
      final newSpeedResults = [...state.speedResults];
      newSpeedResults.removeWhere((s) => s.ip == ip && s.port == port);
      newSpeedResults.add(result);

      state = state.copyWith(detailedResults: updated, speedResults: newSpeedResults);
    } else {
      logger.warning('$ip 测速失败：${result.error}');

      final updated = state.detailedResults.map((d) {
        if (d.ip == ip && d.port == port) {
          d.speedText = result.error ?? '测速失败';
          d.speedQualified = false;
        }
        return d;
      }).toList();

      state = state.copyWith(detailedResults: updated);
    }
  }

  /// ═══════════════════════════════════════════════════════
  /// 运行延迟扫描（非标模式 / 兼容旧接口）
  /// ═══════════════════════════════════════════════════════
  Future<void> runLatencyScan({
    required int port,
    required int workers,
    required int probes,
    required Duration timeout,
    required double maxLatency,
    List<String>? customIps,
    int? topN,
  }) async {
    if (state.scanning) return;
    _cancelRequested = false;
    state = state.copyWith(scanning: true, results: [], speedResults: [], dcGroups: [], clearSelectedDC: true, detailedResults: []);

    final logger = ref.read(subLoggerProvider);
    final mode = state.scanMode;
    final source = state.scanSource;

    logger.info('开始 ${mode.label} 扫描（${source.label}）');

    try {
      // 1. 生成 IP 列表
      List<String> ips;
      if (customIps != null && customIps.isNotEmpty) {
        ips = customIps;
        logger.info('非标优选：${ips.length} 个待测 IP');
      } else if (source == ScanSource.cfRange) {
        ips = await CfRangeScanner.generateIPs(onLog: (m) => logger.info(m));
        logger.info('标准优选：${ips.length} 个待测 IP');
      } else {
        logger.warning('自定义列表为空');
        state = state.copyWith(scanning: false);
        return;
      }

      // 2. 构造节点行
      final nodes = ips.map((entry) {
        if (entry.contains(':')) return entry;
        return '$entry:$port';
      }).toList();

      // 3. 选择探测函数
      final probe = mode == ScanMode.httpPing ? measureHttpTtfb : measureLatency;

      // 4. 进度节流
      ScanProgress? latestProgress;
      Timer? progressTimer;
      void scheduleFlush() {
        progressTimer ??= Timer(Motion.throttleTick, () {
          progressTimer = null;
          if (latestProgress != null) {
            state = state.copyWith(progress: latestProgress);
          }
          if (latestProgress != null && latestProgress!.done < latestProgress!.total) {
            scheduleFlush();
          }
        });
      }

      // 5. 执行探测
      logger.info('开始探测：${nodes.length} 个 IP，端口=$port，结果限制=${topN ?? "无"}');
      final liveResults = <LatencyResult>[];
      final (results, tested, connected) = await latencyProbeAll(
        nodes,
        timeout: timeout,
        workers: workers,
        probes: probes,
        minSuccessRate: 0.34,
        earlyStopCount: topN,
        maxLatency: maxLatency,
        probe: probe,
        onLog: (m) => logger.info(m),
        isCancelled: () => _cancelRequested,
        onProgress: (done, total, conn) {
          latestProgress = ScanProgress(done: done, total: total, connected: conn);
          scheduleFlush();
        },
        onResult: (r) {
          liveResults.add(r);
          final sorted = [...liveResults]..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
          state = state.copyWith(results: sorted);
        },
      );

      progressTimer?.cancel();

      // 6. 过滤 + 排序 + topN
      var passed = results.where((r) =>
          r.latencyMs != null && (maxLatency <= 0 || r.latencyMs! <= maxLatency)).toList();
      passed.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
      if (topN != null && topN > 0 && passed.length > topN) {
        passed = passed.sublist(0, topN);
      }

      if (_cancelRequested) {
        logger.info('扫描已取消（已完成 $tested 个探测）');
      } else {
        logger.info('扫描完成：测试 $tested / 连通 $connected / 通过 ${passed.length}');
      }

      // 7. 地理定位 CF IP
      for (var i = 0; i < passed.length; i++) {
        final r = passed[i];
        final ep = parseEndpoint(r.node);
        if (ep != null && isCloudflareIp(ep.$1)) {
          final cc = await geolocateCfIp(ep.$1);
          if (cc.isNotEmpty) {
            passed[i] = LatencyResult('${ep.$1}:${ep.$2}#$cc', r.latencyMs, r.jitterMs, r.successCount);
          }
        }
      }

      state = state.copyWith(
        scanning: false,
        clearProgress: true,
        results: passed,
        lastTested: tested,
        lastConnected: connected,
      );

      NotificationHelper.taskComplete(
        taskName: '${mode.label} 扫描完成',
        summary: '测试 $tested / 连通 $connected / 通过 ${passed.length}',
      );
    } catch (e) {
      logger.error('扫描失败：$e');
      state = state.copyWith(scanning: false, clearProgress: true);
      NotificationHelper.taskFailed(taskName: '扫描', error: e.toString());
    }
  }

  /// ═══════════════════════════════════════════════════════
  /// 批量速度测试
  /// ═══════════════════════════════════════════════════════
  Future<void> runSpeedTest({
    required String sourceUrl,
    int workers = 5,
    Duration timeout = const Duration(seconds: 15),
    double? minSpeedMBps,
    int? topN,
  }) async {
    if (state.speedTesting || state.results.isEmpty) return;
    _cancelRequested = false;
    state = state.copyWith(speedTesting: true, speedResults: []);

    final logger = ref.read(subLoggerProvider);
    logger.info('开始速度测试（${state.results.length} 个 IP）');

    try {
      final targets = <(String, int)>[];
      for (final r in state.results) {
        final ep = parseEndpoint(r.node);
        if (ep != null) targets.add((ep.$1, ep.$2));
      }

      SpeedProgress? latestProgress;
      Timer? progressTimer;
      void scheduleFlush() {
        progressTimer ??= Timer(Motion.throttleTick, () {
          progressTimer = null;
          if (latestProgress != null) {
            state = state.copyWith(speedProgress: latestProgress);
          }
          if (latestProgress != null && latestProgress!.done < latestProgress!.total) {
            scheduleFlush();
          }
        });
      }

      final results = await SpeedTester.testBatch(
        targets,
        sourceUrl: sourceUrl,
        workers: workers,
        timeout: timeout,
        isCancelled: () => _cancelRequested,
        onProgress: (done, total, bestSpeed) {
          latestProgress = SpeedProgress(done: done, total: total, bestSpeedMBps: bestSpeed);
          scheduleFlush();
        },
      );

      progressTimer?.cancel();

      var filtered = minSpeedMBps != null && minSpeedMBps > 0
          ? results.where((r) => r.success && r.speedMBps >= minSpeedMBps).toList()
          : results.where((r) => r.success).toList();
      filtered.sort((a, b) => b.speedMBps.compareTo(a.speedMBps));
      if (topN != null && topN > 0 && filtered.length > topN) {
        filtered = filtered.sublist(0, topN);
      }

      logger.info('速度测试完成：${results.length} 个测试 / ${filtered.length} 个通过');

      state = state.copyWith(
        speedTesting: false,
        clearSpeedProgress: true,
        speedResults: filtered,
      );
    } catch (e) {
      logger.error('速度测试失败：$e');
      state = state.copyWith(speedTesting: false, clearSpeedProgress: true);
    }
  }

  /// 一键运行（非标模式兼容）：先延迟扫描，再速度测试。
  Future<void> runFullScan({
    required int port,
    required int workers,
    required int probes,
    required Duration timeout,
    required double maxLatency,
    required int latencyTopN,
    List<String>? customIps,
    required bool withSpeedTest,
    required String speedSourceUrl,
    required double minSpeedMBps,
    required int speedTopN,
  }) async {
    await runLatencyScan(
      port: port,
      workers: workers,
      probes: probes,
      timeout: timeout,
      maxLatency: maxLatency,
      customIps: customIps,
      topN: latencyTopN,
    );

    if (_cancelRequested) return;

    if (withSpeedTest && state.results.isNotEmpty) {
      await runSpeedTest(
        sourceUrl: speedSourceUrl,
        workers: workers.clamp(1, 10),
        timeout: const Duration(seconds: 15),
        minSpeedMBps: minSpeedMBps,
        topN: speedTopN,
      );
    }
  }
}

final scannerProvider = StateNotifierProvider<ScannerNotifier, ScannerState>(
  (ref) => ScannerNotifier(ref),
);
