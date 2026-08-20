import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:cfnb_app/features/results/result_state.dart';

/// 导出格式枚举，对应五种常用代理客户端格式。
enum ExportFormat {
  /// CSV 表格格式
  csv,

  /// Clash YAML 代理列表格式
  clashYaml,

  /// V2Ray / Xray JSON 出站配置格式
  v2rayJson,

  /// sing-box JSON 出站配置格式
  singboxJson,

  /// 纯文本 ip:port 格式（每行一个）
  plain;

  /// 用于 UI 显示的中文标签。
  String get label {
    switch (this) {
      case ExportFormat.csv:
        return 'CSV';
      case ExportFormat.clashYaml:
        return 'Clash YAML';
      case ExportFormat.v2rayJson:
        return 'V2Ray JSON';
      case ExportFormat.singboxJson:
        return 'sing-box JSON';
      case ExportFormat.plain:
        return '纯文本 ip:port';
    }
  }

  /// 用于菜单项的图标。
  IconData get icon {
    switch (this) {
      case ExportFormat.csv:
        return Icons.table_chart;
      case ExportFormat.clashYaml:
        return Icons.code;
      case ExportFormat.v2rayJson:
        return Icons.data_object;
      case ExportFormat.singboxJson:
        return Icons.developer_board;
      case ExportFormat.plain:
        return Icons.text_snippet;
    }
  }
}

/// 结果导出器：将优选后的节点列表转换为各种代理客户端格式。
///
/// 所有方法均为静态方法，输入 [ResultRow] 列表，输出格式化字符串。
class ResultExporter {
  ResultExporter._();

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  /// 从 [ResultRow.ipPort] 解析 IP 和端口。
  /// 支持 IPv4 (`1.2.3.4:443`) 和 IPv6 方括号格式 (`[2001:db8::1]:443`)。
  static (String ip, int port)? _parseIpPort(String ipPort) {
    final result = parseEndpoint(ipPort);
    if (result == null) return null;
    return (result.$1, result.$2);
  }

  /// 根据来源字符串自动检测协议类型。
  /// 匹配规则：来源中含 `vmess` 返回 `vmess`，含 `trojan` 返回 `trojan`，
  /// 其余默认返回 `ss`（Shadowsocks）。
  static String _detectProtocol(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('vmess')) return 'vmess';
    if (lower.contains('trojan')) return 'trojan';
    return 'ss';
  }

  /// IPv6 加方括号（Clash/sing-box/V2Ray 的 server 字段要求）。
  static String _ipForServer(String ip) => isIpv6(ip) ? '[$ip]' : ip;

  /// 将 [ResultRow] 转换为 (ip, port, country, latency, source) 五元组，
  /// 供各导出方法复用。
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

  // ---------------------------------------------------------------------------
  // CSV
  // ---------------------------------------------------------------------------

  /// 将节点列表导出为 CSV 格式。
  ///
  /// 表头：`ip,port,country,latency_ms,source`
  /// - IP 和端口从 `ipPort` 解析，支持 IPv6 `[addr]:port` 格式。
  /// - 延迟值从 `"50.00 ms"` 等字符串中提取数值。
  static String toCsv(List<ResultRow> rows) {
    final buf = StringBuffer('ip,port,country,latency_ms,source');
    for (final e in _buildEntries(rows)) {
      buf.writeln();
      buf.write('${e.ip},${e.port},${e.country},${e.latency ?? ''},${e.source}');
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Clash YAML
  // ---------------------------------------------------------------------------

  /// 将节点列表导出为 Clash `proxies:` YAML 片段。
  ///
  /// 每个节点生成一条 proxy 记录：
  /// - 自动检测协议类型（ss / vmess / trojan），默认 `ss`
  /// - SS 节点：`cipher: auto`, `password: placeholder`
  /// - VMess 节点：`uuid` 使用占位符，`alterId: 0`, `cipher: auto`
  /// - 输出仅包含 `proxies:` 部分，用户可自行合并到完整 Clash 配置中。
  static String toClashYaml(List<ResultRow> rows) {
    final buf = StringBuffer('proxies:');
    for (final e in _buildEntries(rows)) {
      final proto = _detectProtocol(e.source);
      final name = e.country.isNotEmpty
          ? '${_ipForServer(e.ip)}:${e.port} ${e.country}'
          : '${_ipForServer(e.ip)}:${e.port}';
      buf.writeln();
      buf.writeln('  - name: "$name"');
      buf.writeln('    type: $proto');
      buf.writeln('    server: ${_ipForServer(e.ip)}');
      buf.writeln('    port: ${e.port}');
      if (proto == 'ss') {
        buf.writeln('    cipher: auto');
        buf.writeln('    password: placeholder');
      } else if (proto == 'vmess') {
        buf.writeln('    uuid: 00000000-0000-0000-0000-000000000000');
        buf.writeln('    alterId: 0');
        buf.writeln('    cipher: auto');
      } else if (proto == 'trojan') {
        buf.writeln('    password: placeholder');
      }
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // V2Ray / Xray JSON
  // ---------------------------------------------------------------------------

  /// 将节点列表导出为 V2Ray / Xray 出站配置 JSON 数组。
  ///
  /// 每个节点生成一个出站（outbound）对象：
  /// - `protocol`：自动检测，默认 `vmess`
  /// - `settings`：协议对应的服务器配置
  /// - `streamSettings`：使用 `tcp` 传输层
  static String toV2rayJson(List<ResultRow> rows) {
    final outbounds = <Map<String, dynamic>>[];
    for (final e in _buildEntries(rows)) {
      final proto = _detectProtocol(e.source);
      Map<String, dynamic> settings;
      if (proto == 'ss') {
        settings = {
          'servers': [
            {
              'address': _ipForServer(e.ip),
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
              'address': _ipForServer(e.ip),
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
              'address': _ipForServer(e.ip),
              'port': e.port,
              'password': 'placeholder',
            }
          ],
        };
      }
      outbounds.add({
        'protocol': proto,
        'settings': settings,
        'streamSettings': {
          'network': 'tcp',
        },
      });
    }
    return const JsonEncoder.withIndent('  ').convert(outbounds);
  }

  // ---------------------------------------------------------------------------
  // sing-box JSON
  // ---------------------------------------------------------------------------

  /// 将节点列表导出为 sing-box 1.8+ 出站配置 JSON 数组。
  ///
  /// 每个节点生成一个出站对象：
  /// - `type`：自动检测协议，默认 `shadowsocks`
  /// - 包含 `server`、`server_port` 等必要字段
  static String toSingboxJson(List<ResultRow> rows) {
    final outbounds = <Map<String, dynamic>>[];
    for (final e in _buildEntries(rows)) {
      final proto = _detectProtocol(e.source);
      final entry = <String, dynamic>{
        'type': proto == 'ss' ? 'shadowsocks' : proto,
        'server': _ipForServer(e.ip),
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
      outbounds.add(entry);
    }
    return const JsonEncoder.withIndent('  ').convert(outbounds);
  }

  // ---------------------------------------------------------------------------
  // 纯文本
  // ---------------------------------------------------------------------------

  /// 将节点列表导出为纯文本格式，每行一个 `ip:port`。
  ///
  /// IPv6 地址会自动加上方括号：`[2001:db8::1]:443`。
  static String toPlain(List<ResultRow> rows) {
    final buf = StringBuffer();
    for (final e in _buildEntries(rows)) {
      final addr = isIpv6(e.ip) ? '[${e.ip}]:${e.port}' : '${e.ip}:${e.port}';
      buf.writeln(addr);
    }
    return buf.toString().trimRight();
  }

  /// 统一导出入口：根据 [format] 选择对应的导出方法。
  static String export(List<ResultRow> rows, ExportFormat format) {
    switch (format) {
      case ExportFormat.csv:
        return toCsv(rows);
      case ExportFormat.clashYaml:
        return toClashYaml(rows);
      case ExportFormat.v2rayJson:
        return toV2rayJson(rows);
      case ExportFormat.singboxJson:
        return toSingboxJson(rows);
      case ExportFormat.plain:
        return toPlain(rows);
    }
  }
}
