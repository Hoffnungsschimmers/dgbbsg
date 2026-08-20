import 'dart:convert';
import 'dart:io';

import '../net/ip.dart';
import 'latency_prober.dart';

/// 延迟优选（纯「裸 TCP 建连」延迟测试，对齐代理软件 urltest 语义）：
/// 1. 对所有节点做并发「裸 TCP 建连」延迟测试（网络层真实 RTT，不受 TLS/SNI 影响）。
/// 2. 按延迟升序排名，仅保留延迟 ≤ [latencyMaxMs] 的节点（该上限为 0/负表示不限）。
/// 3. 取前 [topN] 名（0/负表示全部保留）。输出带名次（#1 = 延迟最低）。
class LatencyFilter {
  /// 运行完整流程。返回 (保留节点列表, 测试数, 连通数)。
  static Future<(List<String>, int, int)> run({
    required List<String> nodes,
    required String outputFile,
    required int latencyMaxMs,
    required Duration timeout,
    required int workers,
    int probes = 1,
    double minSuccessRate = 1.0,
    int topN = 200,
    Map<String, String>? nodeSource,
    Future<(double?, double?, int)> Function(String ip, int port, Duration timeout, {int probes, bool Function()? isCancelled})? probe,
    void Function(String)? onLog,
    bool Function()? isCancelled,
    void Function(int done, int total, int connected)? onProgress,
  }) async {
    final (ordered, tested, connected) = await latencyProbeAll(
      nodes,
      timeout: timeout,
      workers: workers,
      probes: probes,
      minSuccessRate: minSuccessRate,
      nodeSource: nodeSource,
      probe: probe,
      onLog: onLog,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );

    final connectedResults = ordered.where((r) => r.latencyMs != null).toList();

    // 对 Cloudflare IP 做 cdn-cgi/trace 真实落地 POP 检测。
    // 用当前网络的实际响应 POP 覆盖节点名里的国家码，
    // 这样换设备/换网络重跑时会得到该网络下的真实落地。
    final cfTraceMap = <String, String>{}; // ip -> 真实 POP 国家码
    final cfIps = <String>{};
    for (final r in connectedResults) {
      final ep = parseEndpoint(r.node);
      if (ep != null && isCloudflareIp(ep.$1)) {
        cfIps.add(ep.$1);
      }
    }
    if (cfIps.isNotEmpty) {
      onLog?.call('正在通过 cdn-cgi/trace 检测 ${cfIps.length} 个 CF IP 的真实落地…');
      final batchResult = await geolocateCfIpBatch(
        cfIps.toList(),
        timeout: const Duration(milliseconds: 3000),
      );
      cfTraceMap.addAll(batchResult);
      if (cfTraceMap.isNotEmpty) {
        onLog?.call('cdn-cgi/trace 完成：${cfTraceMap.length}/${cfIps.length} 个 CF IP 识别到落地。');
      }
    }

    // 仅保留延迟 ≤ latencyMaxMs 的节点（0/负表示不限）。
    final capped = latencyMaxMs > 0
        ? connectedResults.where((r) => r.latencyMs! <= latencyMaxMs).toList()
        : connectedResults;

    // 加权综合评分：延迟 + 抖动，越低越好。
    // Score = latency + jitter * 0.5（抖动权重 50%）
    // 多次探测取最小值时抖动小的节点更稳定，应排名更前。
    final sorted = capped.toList()
      ..sort((a, b) {
        final sa = a.latencyMs! + (a.jitterMs ?? 0) * 0.5;
        final sb = b.latencyMs! + (b.jitterMs ?? 0) * 0.5;
        return sa.compareTo(sb);
      });
    final keptResults = topN > 0 && topN < sorted.length
        ? sorted.take(topN).toList()
        : sorted;

    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    // 纯数据输出：ip:port#真实落地 延迟
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final lat = (r.latencyMs != null) ? '${r.latencyMs!.toStringAsFixed(2)}ms' : '超时';
      // 用 cdn-cgi/trace 真实 POP 覆盖国家码
      final updatedNode = _applyRealLanding(r.node, cfTraceMap);
      final displayNode = _displayNode(updatedNode);
      sb.writeln('$displayNode $lat');
    }
    await out.writeAsString(sb.toString());

    // 结构化 JSON
    final records = <Map<String, Object?>>[];
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final updatedNode = _applyRealLanding(r.node, cfTraceMap);
      final ep = parseEndpoint(updatedNode);
      records.add({
        'rank': i + 1,
        'ip': ep?.$1 ?? '',
        'port': ep?.$2 ?? 0,
        'country': nodeCountry(updatedNode),
        'landing': cfTraceMap[ep?.$1] ?? '', // 真实落地国家码（仅 CF IP 有值）
        'source': nodeSource != null ? (nodeSource[r.node] ?? '') : '',
        'latency_ms': r.latencyMs == null ? null : (r.latencyMs! * 1000).round() / 1000,
        'jitter_ms': r.jitterMs == null ? null : (r.jitterMs! * 1000).round() / 1000,
      });
    }

    final sourceStats = <String, int>{};
    for (final rec in records) {
      final s = (rec['source'] as String).isEmpty ? '未知' : (rec['source'] as String);
      sourceStats[s] = (sourceStats[s] ?? 0) + 1;
    }

    final jsonFile = File('${out.path}.json');
    await jsonFile.writeAsString(jsonEncode({
      'generated_at': ts,
      'tested': tested,
      'connected': connected,
      'passed': capped.length,
      'kept': records.length,
      'source_stats': sourceStats,
      'nodes': records,
    }));

    return (keptResults.map((r) => r.node).toList(), tested, connected);
  }

  /// 用 cdn-cgi/trace 真实 POP 国家码替换节点名中的国家码。
  /// 仅替换 Cloudflare IP（在 [cfTraceMap] 中有记录的 IP）。
  /// 例：`172.64.145.93:443#CN source` + cfTraceMap[172.64.145.93]='SG'
  ///   → `172.64.145.93:443#SG source`
  static String _applyRealLanding(String node, Map<String, String> cfTraceMap) {
    if (cfTraceMap.isEmpty) return node;
    final ep = parseEndpoint(node);
    if (ep == null) return node;
    final realCc = cfTraceMap[ep.$1];
    if (realCc == null || realCc.isEmpty) return node;
    final hashIdx = node.indexOf('#');
    if (hashIdx < 0) return '$node#$realCc';
    final before = node.substring(0, hashIdx);
    final after = node.substring(hashIdx + 1);
    final sepIdx = findCcSourceSep(after);
    if (sepIdx >= 0) {
      final rest = after.substring(sepIdx); // 保留分隔符 + 来源
      return '$before#$realCc$rest';
    }
    return '$before#$realCc';
  }

  /// 将节点字符串中的国家码替换为中文名。
  /// 兼容新旧格式：
  ///   新: `1.2.3.4:443#HK CM` → `1.2.3.4:443#香港 CM`
  ///   旧: `1.2.3.4:443#HK@CM` → `1.2.3.4:443#香港@CM`
  static String _displayNode(String node) {
    final hashIdx = node.indexOf('#');
    if (hashIdx < 0) return node;
    final before = node.substring(0, hashIdx);
    final after = node.substring(hashIdx + 1);
    final sepIdx = findCcSourceSep(after);
    if (sepIdx >= 0) {
      final cc = after.substring(0, sepIdx);
      final rest = after.substring(sepIdx); // 保留分隔符
      return bracketIpv6Host('$before#${countryCodeToName(cc)}$rest');
    }
    return bracketIpv6Host('$before#${countryCodeToName(after)}');
  }
}

