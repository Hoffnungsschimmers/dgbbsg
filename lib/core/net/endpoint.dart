/// 节点行解析工具（`IP:端口#CC 来源 备注`）。
///
/// 从原延迟优选模块中剥离：订阅转换、结果展示、落地检测仍需这些纯解析函数，
/// 删除延迟优选功能后保留在此处。

typedef IpPort = String;

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
    if (closeBracket + 1 >= base.length || base[closeBracket + 1] != ':') {
      return null;
    }
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

/// 从注释尾部（国家码之后的整段）判定来源名。
///
/// 行格式 `#CC 来源名 原始备注` 里两段只用空格分隔，而原始备注本身可能含空格，
/// 所以先用已知源名（订阅配置里的标签）做前缀匹配，多个命中取最长；都不匹配时
/// 退化为第一个空白 token —— 绝大多数源名不含空格，该兜底即为正确值。
String detectSource(String tail, List<String> knownSources) {
  final t = tail.trim();
  if (t.isEmpty) return '';
  final lower = t.toLowerCase();
  var best = '';
  for (final raw in knownSources) {
    final s = raw.trim();
    if (s.isEmpty) continue;
    final ls = s.toLowerCase();
    final hit = lower == ls || lower.startsWith('$ls ');
    if (hit && s.length > best.length) best = s;
  }
  if (best.isNotEmpty) return best;
  return t.split(RegExp(r'\s+')).first;
}

/// 用真实落地国家码替换节点名中的国家码。
/// 仅替换在 [landingMap] 中有记录的 IP，其余节点原样返回。
/// 例：`172.64.145.93:443#CN source` + landingMap[172.64.145.93]='SG'
///   → `172.64.145.93:443#SG source`
String applyRealLanding(String node, Map<String, String> landingMap) {
  if (landingMap.isEmpty) return node;
  final ep = parseEndpoint(node);
  if (ep == null) return node;
  final realCc = landingMap[ep.$1];
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
