import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cfnb_app/core/export/result_exporter.dart';
import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:cfnb_app/features/results/result_state.dart';

/// 完整客户端配置文件格式枚举。
enum FullConfigFormat {
  /// Clash 完整 YAML 配置
  clash,

  /// sing-box 完整 JSON 配置
  singbox,

  /// V2Ray / Xray 完整 JSON 配置
  v2ray;

  /// 用于 UI 显示的标签。
  String get label {
    switch (this) {
      case FullConfigFormat.clash:
        return 'Clash 配置';
      case FullConfigFormat.singbox:
        return 'sing-box 配置';
      case FullConfigFormat.v2ray:
        return 'V2Ray 配置';
    }
  }

  /// 用于菜单项的图标。
  IconData get icon {
    switch (this) {
      case FullConfigFormat.clash:
        return Icons.shield;
      case FullConfigFormat.singbox:
        return Icons.developer_board;
      case FullConfigFormat.v2ray:
        return Icons.data_object;
    }
  }

  /// 配置文件扩展名（含前导点）。
  String get fileExtension {
    switch (this) {
      case FullConfigFormat.clash:
        return '.yaml';
      case FullConfigFormat.singbox:
        return '.json';
      case FullConfigFormat.v2ray:
        return '.json';
    }
  }
}

/// 完整代理客户端配置生成器。
///
/// 将 [ResultRow] 列表转换为可直接导入使用的完整配置文件内容，
/// 而不仅仅是代理节点列表。所有方法均为静态方法。
class ConfigGenerator {
  ConfigGenerator._();

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  /// 从 [ResultRow.ipPort] 解析 IP 和端口。
  static (String ip, int port)? _parseIpPort(String ipPort) {
    final result = parseEndpoint(ipPort);
    if (result == null) return null;
    return (result.$1, result.$2);
  }

  /// 根据来源字符串自动检测协议类型。
  static String _detectProtocol(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('vmess')) return 'vmess';
    if (lower.contains('trojan')) return 'trojan';
    return 'ss';
  }

  /// 构建条目列表，供各生成方法复用。
  static List<({String ip, int port, String country, double? latency, String source})>
      _buildEntries(List<ResultRow> rows) {
    final entries = <({String ip, int port, String country, double? latency, String source})>[];
    for (final row in rows) {
      final parsed = _parseIpPort(row.ipPort);
      if (parsed == null) continue;
      entries.add((
        ip: parsed.$1,
        port: parsed.$2,
        country: nodeCountry(row.node),
        latency: parseLatency(row.latency),
        source: row.source,
      ));
    }
    return entries;
  }

  /// 生成代理节点名称。
  static String _proxyName(({String ip, int port, String country, double? latency, String source}) e) {
    return e.country.isNotEmpty
        ? '${e.ip}:${e.port} ${e.country}'
        : '${e.ip}:${e.port}';
  }

  // ---------------------------------------------------------------------------
  // Clash 完整 YAML 配置
  // ---------------------------------------------------------------------------

  /// 生成完整的 Clash YAML 配置文件。
  ///
  /// 包含基础设置、`proxies`、`proxy-groups` 和 `rules` 四个部分，
  /// 可直接保存为 `.yaml` 文件导入 Clash。
  static String generateClashConfig(List<ResultRow> rows, {String? subUrl}) {
    final buf = StringBuffer();

    // ---- 基础设置 ----
    buf.writeln('# Clash 完整配置 - 由 cfnb 自动生成');
    buf.writeln('port: 7890');
    buf.writeln('socks-port: 7891');
    buf.writeln('allow-lan: true');
    buf.writeln('mode: rule');
    buf.writeln('log-level: info');
    if (subUrl != null && subUrl.isNotEmpty) {
      buf.writeln();
      buf.writeln('# 订阅地址');
      buf.writeln('sub-url: "$subUrl"');
    }
    buf.writeln();

    // ---- proxies ----
    // 复用 ResultExporter 的代理列表输出
    buf.writeln(ResultExporter.toClashYaml(rows));
    buf.writeln();

    // ---- proxy-groups ----
    buf.writeln('proxy-groups:');
    // 节点选择（select）
    buf.writeln('  - name: "🚀 节点选择"');
    buf.writeln('    type: select');
    buf.writeln('    proxies:');
    for (final e in _buildEntries(rows)) {
      buf.writeln('      - "${_proxyName(e)}"');
    }
    buf.writeln();
    // 自动选择（url-test）
    buf.writeln('  - name: "♻️ 自动选择"');
    buf.writeln('    type: url-test');
    buf.writeln('    url: http://www.gstatic.com/generate_204');
    buf.writeln('    interval: 300');
    buf.writeln('    proxies:');
    for (final e in _buildEntries(rows)) {
      buf.writeln('      - "${_proxyName(e)}"');
    }
    buf.writeln();
    // 漏网之鱼（select）
    buf.writeln('  - name: "🐟 漏网之鱼"');
    buf.writeln('    type: select');
    buf.writeln('    proxies:');
    buf.writeln('      - DIRECT');
    buf.writeln('      - "🚀 节点选择"');
    buf.writeln('      - "♻️ 自动选择"');
    buf.writeln();

    // ---- rules ----
    buf.writeln('rules:');
    buf.writeln('  - DOMAIN-SUFFIX,cn,DIRECT');
    buf.writeln('  - DOMAIN-KEYWORD,google,🚀 节点选择');
    buf.writeln('  - DOMAIN-KEYWORD,github,🚀 节点选择');
    buf.writeln('  - GEOIP,CN,DIRECT');
    buf.writeln('  - MATCH,🐟 漏网之鱼');

    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // sing-box 完整 JSON 配置
  // ---------------------------------------------------------------------------

  /// 生成完整的 sing-box JSON 配置文件。
  ///
  /// 包含 `log`、`inbounds`（mixed 入站，端口 7890）、`outbounds`（含自动选择组、
  /// direct、block 出站）和 `route`（基本路由规则）。
  static String generateSingboxConfig(List<ResultRow> rows) {
    final entries = _buildEntries(rows);
    final proxyOutbounds = <Map<String, dynamic>>[];
    final proxyTags = <String>[];

    for (final e in entries) {
      final proto = _detectProtocol(e.source);
      final tag = _proxyName(e);
      proxyTags.add(tag);
      final entry = <String, dynamic>{
        'type': proto == 'ss' ? 'shadowsocks' : proto,
        'tag': tag,
        'server': e.ip,
        'server_port': e.port,
      };
      if (proto == 'ss') {
        entry['method'] = 'auto';
        entry['password'] = 'placeholder';
      } else if (proto == 'vmess') {
        entry['uuid'] = '00000000-0000-0000-0000-000000000000';
        entry['alter_id'] = 0;
        entry['security'] = 'auto';
        entry['transport'] = {'type': 'tcp'};
      } else if (proto == 'trojan') {
        entry['password'] = 'placeholder';
        entry['transport'] = {'type': 'tcp'};
      }
      proxyOutbounds.add(entry);
    }

    final config = <String, dynamic>{
      'log': {
        'level': 'info',
        'timestamp': true,
      },
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': 7890,
        },
      ],
      'outbounds': [
        {
          'type': 'selector',
          'tag': '🚀 节点选择',
          'outbounds': [
            '♻️ 自动选择',
            'direct',
            ...proxyTags,
          ],
        },
        {
          'type': 'urltest',
          'tag': '♻️ 自动选择',
          'outbounds': proxyTags,
          'url': 'http://www.gstatic.com/generate_204',
          'interval': '300s',
        },
        ...proxyOutbounds,
        {
          'type': 'direct',
          'tag': 'direct',
        },
        {
          'type': 'block',
          'tag': 'block',
        },
      ],
      'route': {
        'rules': [
          {
            'domain_suffix': ['.cn'],
            'outbound': 'direct',
          },
          {
            'domain_keyword': ['google', 'github'],
            'outbound': '🚀 节点选择',
          },
          {
            'ip_cidr': [
              '10.0.0.0/8',
              '172.16.0.0/12',
              '192.168.0.0/16',
            ],
            'outbound': 'direct',
          },
        ],
        'final': '🚀 节点选择',
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }

  // ---------------------------------------------------------------------------
  // V2Ray / Xray 完整 JSON 配置
  // ---------------------------------------------------------------------------

  /// 生成完整的 V2Ray / Xray JSON 配置文件。
  ///
  /// 包含 `inbounds`（socks 1080 + http 1081）、`outbounds`（第一个节点为主出站 +
  /// freedom 出站）和 `routing`（基本路由规则）。
  static String generateV2rayConfig(List<ResultRow> rows) {
    final entries = _buildEntries(rows);

    // 构建代理出站列表
    final proxyOutbounds = <Map<String, dynamic>>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final proto = _detectProtocol(e.source);
      Map<String, dynamic> settings;
      if (proto == 'ss') {
        settings = {
          'servers': [
            {
              'address': e.ip,
              'port': e.port,
              'method': 'auto',
              'password': 'placeholder',
            }
          ],
        };
      } else if (proto == 'vmess') {
        settings = {
          'vnext': [
            {
              'address': e.ip,
              'port': e.port,
              'users': [
                {
                  'id': '00000000-0000-0000-0000-000000000000',
                  'alterId': 0,
                  'security': 'auto',
                }
              ],
            }
          ],
        };
      } else {
        // trojan
        settings = {
          'servers': [
            {
              'address': e.ip,
              'port': e.port,
              'password': 'placeholder',
            }
          ],
        };
      }
      proxyOutbounds.add({
        'tag': 'proxy-$i',
        'protocol': proto,
        'settings': settings,
        'streamSettings': {
          'network': 'tcp',
        },
      });
    }

    // 构建完整配置
    final config = <String, dynamic>{
      'log': {
        'loglevel': 'info',
      },
      'inbounds': [
        {
          'tag': 'socks-in',
          'port': 1080,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
          },
        },
        {
          'tag': 'http-in',
          'port': 1081,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {
            'auth': 'noauth',
          },
        },
      ],
      'outbounds': [
        ...proxyOutbounds,
        if (proxyOutbounds.isEmpty)
          <String, dynamic>{
            'tag': 'proxy',
            'protocol': 'freedom',
            'settings': <String, dynamic>{},
          },
        <String, dynamic>{
          'tag': 'direct',
          'protocol': 'freedom',
          'settings': <String, dynamic>{},
        },
      ],
      'routing': {
        'domainStrategy': 'IPIfNonMatch',
        'balancers': [
          if (proxyOutbounds.isNotEmpty)
            {
              'tag': 'balancer',
              'selector': ['proxy-'],
            },
        ],
        'rules': [
          {
            'type': 'field',
            'domain': ['domain:cn'],
            'outboundTag': 'direct',
          },
          {
            'type': 'field',
            'domain': ['geosite:google', 'geosite:github'],
            if (proxyOutbounds.isNotEmpty)
              'balancerTag': 'balancer'
            else
              'outboundTag': 'proxy',
          },
          {
            'type': 'field',
            'ip': ['geoip:private', 'geoip:cn'],
            'outboundTag': 'direct',
          },
        ],
      },
    };

    return const JsonEncoder.withIndent('  ').convert(config);
  }
}
