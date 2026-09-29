import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 连续失败多少轮后告警一次。
const int sourceFailureAlertThreshold = 3;

/// 订阅源健康度的持久化。
///
/// 存在 SharedPreferences 的独立键而非 `AppConfig` 里：这是运行时统计，
/// 不该跟着配置一起导出、也不该被 WebDAV 恢复配置时覆盖回旧值。
class SourceHealth {
  static const prefsKey = 'source_health_json';

  /// 读取计数；缺键或内容损坏时返回空表（不影响主流程）。
  static Map<String, int> fromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return m.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    } on Object {
      return {};
    }
  }

  static Future<void> saveToPrefs(SharedPreferences prefs, Map<String, int> streaks) =>
      prefs.setString(prefsKey, jsonEncode(streaks));
}

/// 更新连续失败计数。
///
/// [allSources] 为本轮尝试过的全部来源名，[failed] 为其中失败的。
/// 成功的清零（不写入即代表 0）；已从配置里消失的源不再保留。
Map<String, int> updateFailureStreaks(
  Map<String, int> prev, {
  required Iterable<String> allSources,
  required Set<String> failed,
}) {
  final next = <String, int>{};
  for (final s in allSources) {
    if (!failed.contains(s)) continue;
    next[s] = (prev[s] ?? 0) + 1;
  }
  return next;
}

/// 本轮「刚好跨过阈值」的来源：只在达到阈值那一次返回，
/// 之后每轮继续失败不再重复告警，避免通知轰炸。
List<String> sourcesCrossedThreshold(
  Map<String, int> before,
  Map<String, int> after, {
  int threshold = sourceFailureAlertThreshold,
}) {
  final out = <String>[];
  for (final e in after.entries) {
    if (e.value >= threshold && (before[e.key] ?? 0) < threshold) out.add(e.key);
  }
  out.sort();
  return out;
}
