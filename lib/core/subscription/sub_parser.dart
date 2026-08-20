import 'dart:convert';

/// 所有支持的代理协议 scheme 前缀（含尾部 `://`）。
/// 在 [SubParser] 与 [subscription_converter] 中共用，避免重复定义。
const supportedSchemes = [
  'vless://',
  'vmess://',
  'trojan://',
  'ss://',
  'ssr://',
  'hysteria2://',
  'hy2://',
  'tuic://',
];

/// 订阅链接解析（对应旧版 subscription 的解析函数）。
///
/// 支持 vless/vmess/trojan/ss/ssr/hysteria2/hy2/tuic 协议，输出 (host, port, name)。
class SubParser {

  /// 宽松 base64 解码，兼容标准/URL-safe 及缺失填充。
  static String? b64DecodeLoose(String text) {
    final s = text.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return null;
    final pad = s + ('=' * (-s.length % 4));
    for (final decoder in const [false, true]) {
      try {
        final bytes = decoder
            ? base64Url.decode(pad)
            : base64.decode(pad);
        return utf8.decode(bytes, allowMalformed: true);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static ({String host, int port, String name})? parseUriStyle(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    var host = uri.host;
    var port = uri.port;

    // ss:// 可能是 ss://base64(method:pass@host:port)#name
    if (host.isEmpty && link.startsWith('ss://')) {
      var body = link.substring('ss://'.length);
      var frag = '';
      if (body.contains('#')) {
        final parts = body.split('#');
        body = parts[0];
        frag = parts.sublist(1).join('#');
      }
      final decoded = b64DecodeLoose(body.split('?').first);
      if (decoded != null && decoded.contains('@')) {
        final hostport = decoded.substring(decoded.lastIndexOf('@') + 1);
        if (hostport.contains(':')) {
          final idx = hostport.lastIndexOf(':');
          host = hostport.substring(0, idx).replaceAll(RegExp(r'[\[\]]'), '');
          port = int.tryParse(hostport.substring(idx + 1)) ?? 0;
        }
      }
      final name = _unquote(frag).trim();
      if (host.isNotEmpty && port > 0) return (host: host, port: port, name: name);
      return null;
    }

    if (host.isEmpty || port <= 0) return null;
    var name = _unquote(uri.fragment).trim();
    if (name.isEmpty) {
      final qs = uri.queryParameters;
      for (final key in const ['remarks', 'remark', 'name']) {
        if (qs.containsKey(key) && qs[key]!.isNotEmpty) {
          name = _unquote(qs[key]!).trim();
          break;
        }
      }
    }
    return (host: host, port: port, name: name);
  }

  static ({String host, int port, String name})? parseVmess(String link) {
    final payload = link.substring('vmess://'.length).trim();
    final decoded = b64DecodeLoose(payload);
    if (decoded == null) return null;
    try {
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final host = (data['add'] ?? '').toString().trim();
      final portRaw = data['port'];
      final name = (data['ps'] ?? '').toString().trim();
      if (host.isEmpty || portRaw == null) return null;
      final port = int.tryParse(portRaw.toString().trim());
      if (port == null || port <= 0) return null;
      return (host: host, port: port, name: name);
    } on FormatException {
      return null;
    }
  }

  /// 解析 SSR 链接：ssr://base64(server:port:protocol:method:obfs:base64pass/?params)
  static ({String host, int port, String name})? parseSsr(String link) {
    final payload = link.substring('ssr://'.length).trim();
    final decoded = b64DecodeLoose(payload);
    if (decoded == null) return null;

    // Split by '/' first to separate main part from params
    final slashIdx = decoded.indexOf('/?');
    final mainPart = slashIdx >= 0 ? decoded.substring(0, slashIdx) : decoded;
    final paramPart = slashIdx >= 0 ? decoded.substring(slashIdx + 2) : '';

    // Main part: server:port:protocol:method:obfs:base64pass
    final segments = mainPart.split(':');
    if (segments.length < 6) return null;

    final host = segments[0];
    final port = int.tryParse(segments[1]);
    if (host.isEmpty || port == null || port <= 0) return null;

    // segments[5] contains the base64-encoded password; not needed for host/port/name

    // Parse query params for remarks
    var name = '';
    if (paramPart.isNotEmpty) {
      final params = <String, String>{};
      for (final pair in paramPart.split('&')) {
        final eqIdx = pair.indexOf('=');
        if (eqIdx > 0) {
          params[pair.substring(0, eqIdx)] = pair.substring(eqIdx + 1);
        }
      }
      // remarks is base64-encoded
      if (params.containsKey('remarks') && params['remarks']!.isNotEmpty) {
        name = b64DecodeLoose(params['remarks']!) ?? '';
      }
      if (name.isEmpty && params.containsKey('group') && params['group']!.isNotEmpty) {
        name = b64DecodeLoose(params['group']!) ?? '';
      }
    }

    return (host: host, port: port, name: name);
  }

  /// 解析 Trojan 链接：trojan://password@host:port#name?params
  static ({String host, int port, String name})? parseTrojan(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    final host = uri.host;
    final port = uri.port;
    if (host.isEmpty || port <= 0) return null;

    var name = _unquote(uri.fragment).trim();
    if (name.isEmpty) {
      final qs = uri.queryParameters;
      for (final key in const ['remarks', 'remark', 'name']) {
        if (qs.containsKey(key) && qs[key]!.isNotEmpty) {
          name = _unquote(qs[key]!).trim();
          break;
        }
      }
    }
    return (host: host, port: port, name: name);
  }

  /// 从订阅明文解析出所有节点，返回 (host, port, name)。
  static List<({String host, int port, String name})> parseSubscriptionLinks(String text) {
    final results = <({String host, int port, String name})>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      var matched = false;
      for (final scheme in supportedSchemes) {
        if (line.startsWith(scheme)) {
          matched = true;
          break;
        }
      }
      if (!matched) continue;
      final parsed = line.startsWith('vmess://')
          ? parseVmess(line)
          : line.startsWith('ssr://')
              ? parseSsr(line)
              : line.startsWith('trojan://')
                  ? parseTrojan(line)
                  : parseUriStyle(line);
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  static String _unquote(String s) {
    // 去掉 %xx 转义：收集字节后按 UTF-8 解码（与旧版 unquote 等价）
    final bytes = <int>[];
    var i = 0;
    while (i < s.length) {
      if (s[i] == '%' && i + 2 < s.length) {
        final hex = s.substring(i + 1, i + 3);
        final code = int.tryParse(hex, radix: 16);
        if (code != null) {
          bytes.add(code);
          i += 3;
          continue;
        }
      }
      bytes.add(s.codeUnitAt(i));
      i++;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
