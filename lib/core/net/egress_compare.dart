/// 多出口对照探测：同一批 IP 分别经不同出口做 cdn-cgi/trace，
/// 用来回答「这个 anycast IP 在不同网络下到底落到哪」。
library;

/// 一个探测出口：[name] 为展示名，[proxy] 是 `host:port`，空串表示直连。
typedef EgressProfile = ({String name, String proxy});

/// 一条对照观测：某 IP 经某出口得到的机场码 / 国家码，以及该出口的公网 IP。
typedef EgressObservation = ({
  String ip,
  String egress,
  String colo,
  String cc,
  String exitIp,
});

/// 解析配置项 `名称|host:port`。
///
/// 没有 `|` 时整项作名称、按直连处理；`|` 后为空同样是直连。
List<EgressProfile> parseEgressProfiles(List<String> entries) {
  final out = <EgressProfile>[];
  final seen = <String>{};
  for (final raw in entries) {
    final e = raw.trim();
    if (e.isEmpty) continue;
    final i = e.indexOf('|');
    final name = (i < 0 ? e : e.substring(0, i)).trim();
    final proxy = i < 0 ? '' : e.substring(i + 1).trim();
    if (name.isEmpty || !seen.add(name)) continue;
    out.add((name: name, proxy: proxy));
  }
  return out;
}

/// 透视为 `IP → (出口名 → 国家码)`，空国家码记为 `?` 以便与真实码区分。
Map<String, Map<String, String>> pivotByIp(List<EgressObservation> rows) {
  final out = <String, Map<String, String>>{};
  for (final r in rows) {
    (out[r.ip] ??= <String, String>{})[r.egress] = r.cc.isEmpty ? '?' : r.cc;
  }
  return out;
}

/// 落地国家码不一致的 IP 数量（同一 IP 在不同出口下得到不同国家码）。
int countDivergentIps(Map<String, Map<String, String>> pivot) {
  var n = 0;
  for (final m in pivot.values) {
    if (m.values.toSet().length > 1) n++;
  }
  return n;
}

/// 渲染对照 CSV。表头固定，备注类字段不含逗号故无需转义。
String renderComparisonCsv(List<EgressObservation> rows) {
  final sb = StringBuffer('ip,egress,colo,country,exit_ip');
  for (final r in rows) {
    sb.write('\n${r.ip},${r.egress},${r.colo},${r.cc},${r.exitIp}');
  }
  return sb.toString();
}
