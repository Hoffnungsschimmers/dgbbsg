import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../net/ip.dart';

/// 节点解析工具（对应旧版 fetcher 的解析函数）。
///
/// 解析结果统一为 `ip:port#CC` 格式字符串，与旧版保持一致，便于后续探测/测速复用。
class NodeParser {
  final Map<String, String> cnToCode;
  final Map<String, String> alpha3ToAlpha2;
  final Set<String> codeSet;

  NodeParser({
    required this.cnToCode,
    required this.alpha3ToAlpha2,
  }) : codeSet = {...cnToCode.values};

  /// 从任意标签提取标准两位国家代码。
  String? extractCountryCode(String label) {
    label = label.trim();
    if (label.isEmpty) return null;

    final direct = cnToCode[label];
    if (direct != null) return direct;

    final tokens = label.split(RegExp(r'[\s,;|/\-]+'));

    for (final token in tokens) {
      final cleaned = token.replaceAllMapped(
          RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), (m) => '');
      final cn = RegExp(r'^([\u4e00-\u9fff（）()]+)\d*$').firstMatch(cleaned);
      if (cn != null) {
        final code = cnToCode[cn.group(1)!.trim()];
        if (code != null) return code;
      }
    }

    for (final token in tokens) {
      final cleaned = token.replaceAll(RegExp(r'^[\d\s\-_.|#]+'), '').trim();
      final m3 = RegExp(r'^([A-Z]{3})(?![A-Za-z])').firstMatch(cleaned);
      if (m3 != null && alpha3ToAlpha2.containsKey(m3.group(1))) {
        return alpha3ToAlpha2[m3.group(1)];
      }
      final m2 = RegExp(r'^([A-Z]{2})(?![A-Za-z])').firstMatch(cleaned);
      if (m2 != null && codeSet.contains(m2.group(1))) {
        return m2.group(1);
      }
    }

    for (final token in tokens) {
      final noEmoji = token.replaceAllMapped(
          RegExp(r'[\u{1F1E6}-\u{1F1FF}]', unicode: true), (m) => '').trim();
      final cn = RegExp(r'^([\u4e00-\u9fff（）()]+)\d*$').firstMatch(noEmoji);
      if (cn != null) {
        final code = cnToCode[cn.group(1)!.trim()];
        if (code != null) return code;
      }
    }

    final emojiChars = <int>[];
    for (final r in label.runes) {
      if (r >= 0x1F1E6 && r <= 0x1F1FF) emojiChars.add(r);
    }
    if (emojiChars.length >= 2 && emojiChars.length.isEven) {
      final first = emojiChars[0] - 0x1F1E6;
      final second = emojiChars[1] - 0x1F1E6;
      if (first >= 0 && first <= 25 && second >= 0 && second <= 25) {
        return String.fromCharCode(first + 0x41) + String.fromCharCode(second + 0x41);
      }
    }
    return null;
  }

  /// 从纯文本提取标准节点。
  ///
  /// 兼容多种格式：
  /// - `ip:port#CC` / `ip#CC` / `domain:port#CC`
  /// - `ip`（无端口，默认 443）
  /// - 测速结果格式 `ip [延迟 xx ms]` / `ip 延迟xxms` / `ip 12.3Mbps`（剥离注释取 IP）
  /// - 区域优先格式 `HK [延迟 xx ms]`（无 IP，跳过）
  List<String> parseTextNodes(String text) {
    final nodes = <String>[];
    // IPv4
    final ipv4Re = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?::(\d{1,5}))?');
    // IPv6 方括号格式: [2606:4700:52::1]:443
    final ipv6Re = RegExp(r'\[([0-9a-fA-F:]+)\]:(\d{1,5})');
    // 域名
    final domainRe = RegExp(r'([a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,})(?::(\d{1,5}))?');

    for (var token in text.split('\n')) {
      token = token.trim();
      if (token.isEmpty) continue;
      if (token.startsWith('#') || token.startsWith('//')) continue;

      // 拆分标签（# 之后为注释）
      String body = token;
      String label = '';
      if (token.contains('#')) {
        final parts = token.split('#');
        body = parts[0].trim();
        label = parts.sublist(1).join('#').trim();
      }

      String? ipPort;

      // 优先匹配 IPv6 方括号格式
      final v6Match = ipv6Re.firstMatch(body);
      if (v6Match != null) {
        ipPort = '[${v6Match.group(1)}]:${v6Match.group(2)}';
      } else {
        // 裸 IPv6:port（如 2606:4700:...:443，无方括号）
        final bareIpPort = _matchBareIpv6Port(body);
        if (bareIpPort != null) {
          ipPort = bareIpPort;
        } else {
          // 匹配 IPv4
          final ipMatch = ipv4Re.firstMatch(body);
          if (ipMatch != null) {
            final ip = ipMatch.group(1)!;
            final port = ipMatch.group(2);
            ipPort = port != null ? '$ip:$port' : '$ip:443';
          } else {
            // 匹配域名
            final dm = domainRe.firstMatch(body);
            if (dm != null) {
              final domain = dm.group(1)!;
              final port = dm.group(2);
              ipPort = port != null ? '$domain:$port' : '$domain:443';
            }
          }
        }
      }
      if (ipPort == null) continue;

      // 输出格式：ip:port#CC（标准化国家码）
      if (label.isNotEmpty) {
        final cc = extractCountryCode(label);
        if (cc == null) continue; // 无有效国家码则跳过
        nodes.add('$ipPort#$cc');
      } else {
        nodes.add(ipPort);
      }
    }
    return nodes;
  }

  /// 裸 IPv6 主机判定（不含方括号、不以冒号开头/结尾、≥3 段或含 ::）。
  bool _isBareIpv6(String s) {
    if (s.isEmpty || s.startsWith('[') || s.startsWith(':') || s.endsWith(':')) {
      return false;
    }
    if (s.contains(']')) return false;
    if (!s.contains(':')) return false;
    return s.contains('::') || s.split(':').length >= 3;
  }

  /// 从文本匹配裸 IPv6:port，成功返回 `[ip]:port` 字符串。
  /// 贪婪匹配从最长候选回溯，避免 `2606`+`:4700` 这类短候选；
  /// 校验失败的候选自动跳过（allMatches 推进到下一处）。
  String? _matchBareIpv6Port(String body) {
    final re = RegExp(r'([0-9a-fA-F:]+):(\d{1,5})');
    for (final m in re.allMatches(body)) {
      final g1 = m.group(1)!;
      if (_isBareIpv6(g1)) return '[$g1]:${m.group(2)}';
    }
    return null;
  }

  /// 递归从 JSON 结构提取节点。
  List<String> parseJsonNodes(dynamic data) {
    final nodes = <String>[];
    if (data is List) {
      for (final item in data) {
        nodes.addAll(parseJsonNodes(item));
      }
    } else if (data is Map) {
      for (final key in const ['nodes', 'data', 'result', 'list']) {
        if (data[key] is List) {
          nodes.addAll(parseJsonNodes(data[key]));
          break;
        }
      }
      final ip = data['ip'] ?? data['host'];
      final port = data['port'];
      final code = data['country'] ?? data['cc'];
      if (ip != null && port != null && code != null) {
        nodes.add('${bracketIpv6Host('$ip:$port')}#${(code as String).toUpperCase()}');
      }
    } else if (data is String) {
      nodes.addAll(parseTextNodes(data));
    }
    return nodes;
  }

  /// 自适应解析：尝试 JSON，失败回退纯文本。
  List<String> parseAdaptive(String text) {
    text = text.trim();
    if (text.isEmpty) return [];
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        final data = jsonDecode(text);
        return parseJsonNodes(data);
      } on FormatException {
        // 回退文本
      }
    }
    return parseTextNodes(text);
  }

  /// 从打包的 assets/country_codes.json 构建 NodeParser。
  static Future<NodeParser> fromAssets(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    final data = jsonDecode(text) as Map<String, dynamic>;
    return NodeParser(
      cnToCode: Map<String, String>.from(data['CN_TO_CODE'] as Map),
      alpha3ToAlpha2: Map<String, String>.from(data['ALPHA3_TO_ALPHA2'] as Map),
    );
  }
}

