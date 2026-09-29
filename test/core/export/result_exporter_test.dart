import 'dart:convert';

import 'package:cfnb_app/core/export/result_exporter.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 构建测试用 ResultRow 列表。
  List<ResultRow> _makeRows() => [
    ResultRow('1.2.3.4:443#US CM', '50.00 ms'),
    ResultRow('10.0.0.1:8080#HK VMess', '120.50ms'),
    ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms'),
  ];

  group('ExportFormat', () {
    test('label 返回正确的中文标签', () {
      expect(ExportFormat.csv.label, 'CSV');
      expect(ExportFormat.clashYaml.label, 'Clash YAML');
      expect(ExportFormat.v2rayJson.label, 'V2Ray JSON');
      expect(ExportFormat.singboxJson.label, 'sing-box JSON');
      expect(ExportFormat.plain.label, '纯文本 ip:port');
    });
  });

  group('toCsv', () {
    test('输出包含表头和正确的数据行', () {
      final rows = _makeRows();
      final csv = ResultExporter.toCsv(rows);

      // 包含表头
      expect(csv, startsWith('ip,port,country,source'));

      final lines = csv.split('\n');
      // 表头 + 3 行数据
      expect(lines.length, 4);

      // 第一行：IPv4
      expect(lines[1], '1.2.3.4,443,US,CM');

      // 第二行：端口 8080
      expect(lines[2], '10.0.0.1,8080,HK,VMess');

      // 第三行：IPv6
      expect(lines[3], '2001:db8::1,443,JP,Trojan');
    });

    test('空列表只输出表头', () {
      final csv = ResultExporter.toCsv([]);
      expect(csv, 'ip,port,country,source');
    });

    test('行数据与延迟无关（延迟列已移除）', () {
      final rows = [ResultRow('1.2.3.4:443#US CM')];
      final csv = ResultExporter.toCsv(rows);
      final lines = csv.split('\n');
      expect(lines[1], '1.2.3.4,443,US,CM');
    });

    test('来源含逗号时加双引号（原始节点备注常见）', () {
      final rows = [ResultRow('1.2.3.4:443#US 麒麟 美国, Los Angeles 01')];
      final lines = ResultExporter.toCsv(rows).split('\n');
      expect(lines[1], '1.2.3.4,443,US,"麒麟 美国, Los Angeles 01"');
    });

    test('无效的 ipPort 被跳过', () {
      final rows = [
        ResultRow('invalid_node', '50.00 ms'),
        ResultRow('1.2.3.4:443#US', '50.00 ms'),
      ];
      final csv = ResultExporter.toCsv(rows);
      final lines = csv.split('\n');
      // 表头 + 1 行有效数据
      expect(lines.length, 2);
    });
  });

  group('toClashYaml', () {
    test('生成的 YAML 包含 proxies: 头', () {
      final yaml = ResultExporter.toClashYaml(_makeRows());
      expect(yaml, startsWith('proxies:'));
    });

    test('SS 节点包含 cipher 和 password', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final yaml = ResultExporter.toClashYaml(rows);
      expect(yaml, contains('type: ss'));
      expect(yaml, contains('cipher: auto'));
      expect(yaml, contains('password: placeholder'));
    });

    test('VMess 节点包含 uuid 和 alterId', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final yaml = ResultExporter.toClashYaml(rows);
      expect(yaml, contains('type: vmess'));
      expect(yaml, contains('uuid: 00000000-0000-0000-0000-000000000000'));
      expect(yaml, contains('alterId: 0'));
      expect(yaml, contains('cipher: auto'));
    });

    test('Trojan 节点包含 password', () {
      final rows = [ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms')];
      final yaml = ResultExporter.toClashYaml(rows);
      expect(yaml, contains('type: trojan'));
      expect(yaml, contains('password: placeholder'));
    });

    test('IPv6 server 字段带方括号', () {
      final rows = [ResultRow('2001:db8::1:443#US CM', '50.00 ms')];
      final yaml = ResultExporter.toClashYaml(rows);
      expect(yaml, contains('server: [2001:db8::1]'));
      expect(yaml, contains('name: "[2001:db8::1]:443 US"'));
    });

    test('空列表只输出 proxies:', () {
      final yaml = ResultExporter.toClashYaml([]);
      expect(yaml, 'proxies:');
    });
  });

  group('toV2rayJson', () {
    test('输出是合法 JSON 数组', () {
      final json = ResultExporter.toV2rayJson(_makeRows());
      final parsed = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      expect(parsed.length, 3);
    });

    test('SS 出站使用 shadowsocks 服务器格式', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final parsed = (jsonDecode(ResultExporter.toV2rayJson(rows)) as List).cast<Map<String, dynamic>>();
      expect(parsed.first['protocol'], 'ss');
      final servers = parsed.first['settings']['servers'] as List;
      expect(servers.first['address'], '1.2.3.4');
      expect(servers.first['port'], 443);
      expect(servers.first['method'], 'auto');
    });

    test('VMess 出站使用 vnext 格式', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final parsed = (jsonDecode(ResultExporter.toV2rayJson(rows)) as List).cast<Map<String, dynamic>>();
      expect(parsed.first['protocol'], 'vmess');
      final vnext = parsed.first['settings']['vnext'] as List;
      expect(vnext.first['address'], '10.0.0.1');
      expect(vnext.first['port'], 8080);
      final users = vnext.first['users'] as List;
      expect(users.first['id'], '00000000-0000-0000-0000-000000000000');
      expect(users.first['alterId'], 0);
    });

    test('streamSettings 使用 tcp 传输层', () {
      final json = ResultExporter.toV2rayJson(_makeRows());
      final parsed = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      for (final entry in parsed) {
        expect(entry['streamSettings']['network'], 'tcp');
      }
    });

    test('空列表输出空 JSON 数组', () {
      final json = ResultExporter.toV2rayJson([]);
      expect(jsonDecode(json), isEmpty);
    });
  });

  group('toSingboxJson', () {
    test('输出是合法 JSON 数组', () {
      final json = ResultExporter.toSingboxJson(_makeRows());
      final parsed = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      expect(parsed.length, 3);
    });

    test('SS 节点类型为 shadowsocks', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final parsed = (jsonDecode(ResultExporter.toSingboxJson(rows)) as List).cast<Map<String, dynamic>>();
      expect(parsed.first['type'], 'shadowsocks');
      expect(parsed.first['server'], '1.2.3.4');
      expect(parsed.first['server_port'], 443);
      expect(parsed.first['method'], 'auto');
      expect(parsed.first['password'], 'placeholder');
    });

    test('VMess 节点包含 uuid 和 transport', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final parsed = (jsonDecode(ResultExporter.toSingboxJson(rows)) as List).cast<Map<String, dynamic>>();
      expect(parsed.first['type'], 'vmess');
      expect(parsed.first['uuid'], '00000000-0000-0000-0000-000000000000');
      expect(parsed.first['alter_id'], 0);
      expect(parsed.first['security'], 'auto');
      expect(parsed.first['transport']['type'], 'tcp');
    });

    test('Trojan 节点包含 transport', () {
      final rows = [ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms')];
      final parsed = (jsonDecode(ResultExporter.toSingboxJson(rows)) as List).cast<Map<String, dynamic>>();
      expect(parsed.first['type'], 'trojan');
      expect(parsed.first['password'], 'placeholder');
      expect(parsed.first['transport']['type'], 'tcp');
    });

    test('空列表输出空 JSON 数组', () {
      final json = ResultExporter.toSingboxJson([]);
      expect(jsonDecode(json), isEmpty);
    });
  });

  group('toPlain', () {
    test('每行一个 ip:port', () {
      final plain = ResultExporter.toPlain(_makeRows());
      final lines = plain.split('\n');
      expect(lines.length, 3);
      expect(lines[0], '1.2.3.4:443');
      expect(lines[1], '10.0.0.1:8080');
    });

    test('IPv6 地址用方括号包裹', () {
      final plain = ResultExporter.toPlain(_makeRows());
      final lines = plain.split('\n');
      expect(lines[2], '[2001:db8::1]:443');
    });

    test('空列表输出空字符串', () {
      expect(ResultExporter.toPlain([]), '');
    });

    test('无效节点被跳过', () {
      final rows = [
        ResultRow('bad', '50.00 ms'),
        ResultRow('1.2.3.4:443#US', '50.00 ms'),
      ];
      final plain = ResultExporter.toPlain(rows);
      expect(plain, '1.2.3.4:443');
    });
  });
}
