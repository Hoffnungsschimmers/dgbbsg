import 'dart:convert';
import 'dart:io';

/// 某个 IP 一次落地检测的观测记录。
class LandingObservation {
  /// 观测时间，形如 `2026-09-29 20:55:01`。
  final String at;

  /// Cloudflare 机场码（如 HKG）；由归属地兜底得出时为空。
  final String colo;

  /// 两位国家码。
  final String cc;

  /// 本轮测量的出口身份（Cloudflare 看到的源 IP），用于区分不同网络。
  final String egressIp;

  const LandingObservation({
    required this.at,
    this.colo = '',
    this.cc = '',
    this.egressIp = '',
  });

  Map<String, String> toJson() =>
      {'at': at, 'colo': colo, 'cc': cc, 'egress_ip': egressIp};

  static LandingObservation fromJson(Map<Object?, Object?> j) => LandingObservation(
        at: (j['at'] ?? '').toString(),
        colo: (j['colo'] ?? '').toString(),
        cc: (j['cc'] ?? '').toString(),
        egressIp: (j['egress_ip'] ?? '').toString(),
      );
}

/// 每个 IP 最多保留的历史观测条数（新的在前）。同一落地结果连续重复不占历史位。
const int landingHistoryMaxPerIp = 8;

/// 写回前快照最多保留的份数。
const int landingSnapshotKeep = 20;

/// 落地历史：IP → 观测列表（新 → 旧）。
typedef LandingHistory = Map<String, List<LandingObservation>>;

/// 追加一轮观测。
///
/// [results] 为 IP → (colo, cc)；与上一条记录完全相同时**不追加**，
/// 否则每 60 分钟的自动更新会把历史灌满重复项。
LandingHistory appendLandingRound(
  LandingHistory history, {
  required String at,
  required Map<String, ({String colo, String cc})> results,
  String egressIp = '',
}) {
  final next = <String, List<LandingObservation>>{
    for (final e in history.entries) e.key: List.of(e.value),
  };
  for (final e in results.entries) {
    final list = next.putIfAbsent(e.key, () => <LandingObservation>[]);
    final last = list.isEmpty ? null : list.first;
    if (last != null && last.colo == e.value.colo && last.cc == e.value.cc) continue;
    list.insert(
      0,
      LandingObservation(
        at: at,
        colo: e.value.colo,
        cc: e.value.cc,
        egressIp: egressIp,
      ),
    );
    if (list.length > landingHistoryMaxPerIp) {
      list.removeRange(landingHistoryMaxPerIp, list.length);
    }
  }
  return next;
}

/// 序列化为 JSON 文本。
String encodeLandingHistory(LandingHistory history) => jsonEncode({
      for (final e in history.entries)
        e.key: e.value.map((o) => o.toJson()).toList(),
    });

/// 解析 JSON 文本；内容损坏时按空表处理（与归属地缓存同样的容错策略）。
LandingHistory parseLandingHistory(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final out = <String, List<LandingObservation>>{};
    for (final e in decoded.entries) {
      final v = e.value;
      if (v is! List) continue;
      final list = <LandingObservation>[
        for (final item in v)
          if (item is Map<Object?, Object?>) LandingObservation.fromJson(item),
      ];
      if (list.isNotEmpty) out[e.key.toString()] = list;
    }
    return out;
  } catch (_) {
    return {};
  }
}

/// `2026-09-29 20:55:01` → `2026-09-29-20-55-01`，用于文件名且天然按时间排序。
String landingStampFor(String at) => at.replaceAll(RegExp(r'[: ]'), '-');

/// 写回前把当前结果文件复制成带时间戳的快照，防止「一次错误的落地覆盖毁掉好结果」。
/// 返回快照文件；[current] 不存在或复制失败时返回 null。
File? snapshotLandingOutput(File current, Directory dir, String at) {
  try {
    if (!current.existsSync()) return null;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ext = current.path.endsWith('.txt') ? '.txt' : '';
    final name = 'landing_${landingStampFor(at)}$ext';
    final dest = File('${dir.path}${Platform.pathSeparator}$name');
    current.copySync(dest.path);
    pruneLandingSnapshots(dir);
    return dest;
  } catch (_) {
    return null;
  }
}

String _fileName(File f) => f.uri.pathSegments.last;

/// 只保留最近 [keep] 份快照，返回删除的数量。
int pruneLandingSnapshots(Directory dir, {int keep = landingSnapshotKeep}) {
  try {
    if (!dir.existsSync()) return 0;
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final n = _fileName(f);
          return n.startsWith('landing_') && n.endsWith('.txt');
        })
        .toList()
      // 文件名含时间戳，字典序即时间序，倒序即「新 → 旧」。
      ..sort((a, b) => _fileName(b).compareTo(_fileName(a)));
    var removed = 0;
    for (final f in files.skip(keep)) {
      try {
        f.deleteSync();
        removed++;
      } catch (_) {
        // 单个快照删不掉不影响其余
      }
    }
    return removed;
  } catch (_) {
    return 0;
  }
}
