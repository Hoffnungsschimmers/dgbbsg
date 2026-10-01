import 'package:cfnb_app/core/net/egress_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEgressProfiles', () {
    test('名称|host:port 解析为具名代理出口', () {
      expect(parseEgressProfiles(['节点A|127.0.0.1:7890']),
          [(name: '节点A', proxy: '127.0.0.1:7890')]);
    });

    test('| 后留空即直连；没有 | 也按直连处理', () {
      expect(parseEgressProfiles(['本机直连|']), [(name: '本机直连', proxy: '')]);
      expect(parseEgressProfiles(['家宽']), [(name: '家宽', proxy: '')]);
    });

    test('跳过空条目与空名称，重名只留第一个', () {
      expect(
        parseEgressProfiles(['  ', '|127.0.0.1:7890', 'A|', 'A|1.1.1.1:1', 'B|']),
        [
          (name: 'A', proxy: ''),
          (name: 'B', proxy: ''),
        ],
      );
    });

    test('保留名称内部空格（源名可能含空格）', () {
      expect(parseEgressProfiles(['天诚 官方|127.0.0.1:7890']).single.name, '天诚 官方');
    });
  });

  group('pivotByIp / countDivergentIps', () {
    const rows = [
      (ip: '1.1.1.1', egress: '直连', colo: 'HKG', cc: 'HK', exitIp: '9.9.9.9'),
      (ip: '1.1.1.1', egress: '节点A', colo: 'LAX', cc: 'US', exitIp: '8.8.8.8'),
      (ip: '2.2.2.2', egress: '直连', colo: 'NRT', cc: 'JP', exitIp: '9.9.9.9'),
      (ip: '2.2.2.2', egress: '节点A', colo: 'NRT', cc: 'JP', exitIp: '8.8.8.8'),
      (ip: '3.3.3.3', egress: '直连', colo: '', cc: '', exitIp: '9.9.9.9'),
      (ip: '3.3.3.3', egress: '节点A', colo: '', cc: '', exitIp: '8.8.8.8'),
    ];

    test('透视为 IP → 出口 → 国家码，未识别记为 ?', () {
      final p = pivotByIp(rows);
      expect(p['1.1.1.1'], {'直连': 'HK', '节点A': 'US'});
      expect(p['3.3.3.3'], {'直连': '?', '节点A': '?'});
    });

    test('只统计出口间结果不同的 IP', () {
      expect(countDivergentIps(pivotByIp(rows)), 1);
    });

    test('空观测集不报错', () {
      expect(pivotByIp(const []), isEmpty);
      expect(countDivergentIps({}), 0);
    });
  });

  group('renderComparisonCsv', () {
    test('表头固定，每条观测一行', () {
      final csv = renderComparisonCsv(const [
        (ip: '1.1.1.1', egress: '直连', colo: 'HKG', cc: 'HK', exitIp: '9.9.9.9'),
        (ip: '1.1.1.1', egress: '节点A', colo: 'LAX', cc: 'US', exitIp: '8.8.8.8'),
      ]);
      final lines = csv.split('\n');
      expect(lines.first, 'ip,egress,colo,country,exit_ip');
      expect(lines.length, 3);
      expect(lines[1], '1.1.1.1,直连,HKG,HK,9.9.9.9');
      expect(lines[2], '1.1.1.1,节点A,LAX,US,8.8.8.8');
    });

    test('空结果只输出表头', () {
      expect(renderComparisonCsv(const []), 'ip,egress,colo,country,exit_ip');
    });
  });
}
