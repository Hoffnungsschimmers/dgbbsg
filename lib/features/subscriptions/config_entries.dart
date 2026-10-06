import '../../core/subscription/sub_parser.dart' show supportedSchemes;

/// 配置页订阅列表条目的纯解析逻辑，从 `config_tab.dart` 原样抽出以便单测。
///
/// 条目格式：订阅器 `名称|域名|secret`，订阅链接 `备注|URL`。
/// 节点分享链接（`supportedSchemes`）本身不带「备注|」前缀，只有 http(s) 订阅地址
/// 才支持标签前缀——判断必须用 scheme 前缀精确比对，绝不能用 `contains('://')`：
/// 备注自身含 URL 时（`备注A|https://…`）会被误判成节点链接，导致备注丢失、源名错误。

/// 订阅器条目：名称 = 第一个 `|` 段。
String generatorName(String entry) => entry.split('|').first.trim();

/// 订阅器条目：域名 = 第二个 `|` 段（无则整个条目）。
String generatorHost(String entry) {
  final parts = entry.split('|');
  return parts.length > 1 ? parts[1].trim() : entry.trim();
}

/// 订阅器条目：密钥 = 第三个及之后的 `|` 段（secret 自身可含 `|`）。
String generatorSecret(String entry) {
  final parts = entry.split('|');
  return parts.length > 2 ? parts.sublist(2).join('|').trim() : '';
}

/// 订阅链接条目：备注 = 第一个 `|` 段；节点分享链接无备注。
String urlNote(String url) {
  final u = url.trim();
  if (supportedSchemes.any((s) => u.startsWith(s))) return '';
  final pipeIdx = u.indexOf('|');
  if (pipeIdx > 0) return u.substring(0, pipeIdx).trim();
  return '';
}

/// 订阅链接条目：实际链接 = `|` 之后部分（无 `|` 或其后为空则整体）。
String urlValue(String url) {
  final u = url.trim();
  if (supportedSchemes.any((s) => u.startsWith(s))) return u;
  final pipeIdx = u.indexOf('|');
  if (pipeIdx > 0) {
    final after = u.substring(pipeIdx + 1).trim();
    if (after.isNotEmpty) return after;
  }
  return u;
}

/// 备注 + 链接拼回存储格式（节点分享链接不拼备注）。
String joinNoteValue(String note, String value) {
  final v = value.trim();
  if (supportedSchemes.any((s) => v.startsWith(s))) return v;
  final n = note.trim();
  return n.isEmpty ? v : '$n|$v';
}
