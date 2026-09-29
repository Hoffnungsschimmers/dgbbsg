import 'package:cfnb_app/core/net/endpoint.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseResultLines', () {
    test('parses legacy ip.txt with Mbps remnants (dropped) and latency', () {
      const text = '# header\n'
          '1.1.1.1:443#US 120.50 Mbps 30.10 ms\n'
          '2.2.2.2:443#JP 9.80 Mbps 62.10 ms\n';
      final rows = parseResultLines(text);
      expect(rows.length, 2);
      expect(rows[0].ipPort, '1.1.1.1:443');
      expect(rows[0].country, '美国');
      expect(rows[0].latency, '30.10 ms');
    });
    test('parses plain node lines (subscription output)', () {
      const text = '1.1.1.1:443#US\n2.2.2.2:443#JP';
      final rows = parseResultLines(text);
      expect(rows.length, 2);
      expect(rows[0].latency, isNull);
      expect(rows[1].country, '日本');
    });
    test('ipPort strips source (space-separated format)', () {
      const text = 'example.com:2096# 洛璃\n1.1.1.1:443#US CM\n';
      final rows = parseResultLines(text);
      expect(rows[0].ipPort, 'example.com:2096');
      expect(rows[0].source, '洛璃');
      expect(rows[1].ipPort, '1.1.1.1:443');
      expect(rows[1].source, 'CM');
    });
    test('来源名 + 原始备注整体作为 source，国家码仍取首位', () {
      const text = '1.1.1.1:443#US 麒麟 美国 洛杉矶 01\n';
      final rows = parseResultLines(text);
      expect(rows.single.ipPort, '1.1.1.1:443');
      expect(rows.single.annotation, 'US 麒麟 美国 洛杉矶 01');
      expect(rows.single.country, '美国');
      expect(rows.single.source, '麒麟 美国 洛杉矶 01');
      expect(rows.single.latency, isNull);
    });
    test('行尾「120ms」按历史延迟识别，写回不丢字符', () {
      // 已下线的测速格式残留：行尾「数字+ms」会被切成 latency，
      // 但 toText 原样拼回，文件内容不受损。
      const text = '1.1.1.1:443#US 美国 120ms\n';
      final rows = parseResultLines(text);
      expect(rows.single.source, '美国');
      expect(rows.single.latency, '120ms');
      expect(ResultState(rows: rows).toText(), text);
    });
    test('备注中间的「120ms」不切延迟，整段备注保留', () {
      const text = '1.1.1.1:443#US 麒麟 美国 120ms 优化专线\n';
      final rows = parseResultLines(text);
      expect(rows.single.latency, isNull);
      expect(rows.single.annotation, 'US 麒麟 美国 120ms 优化专线');
      expect(rows.single.source, '麒麟 美国 120ms 优化专线');
      expect(ResultState(rows: rows).toText(), text);
    });
  });

  group('filterByFacets / countFacets', () {
    final rows = [
      ResultRow('1.1.1.1:443#US CM 洛杉矶 01'),
      ResultRow('2.2.2.2:443#JP 天诚 Cloudflare 东京'),
      ResultRow('3.3.3.3:443#US 洛璃 圣何塞'),
    ];
    const names = ['CM', '天诚 Cloudflare', '洛璃'];
    String srcOf(ResultRow r) => detectSource(r.source, names);

    test('两个集合都为空时原样返回', () {
      expect(filterByFacets(rows), rows);
    });
    test('按国家码筛选', () {
      final out = filterByFacets(rows, countries: {'US'});
      expect(out.map((e) => e.ipPort), ['1.1.1.1:443', '3.3.3.3:443']);
    });
    test('按来源多选筛选（含空格的源名整体命中）', () {
      final out = filterByFacets(rows, sources: {'天诚 Cloudflare', '洛璃'}, sourceOf: srcOf);
      expect(out.map((e) => e.ipPort), ['2.2.2.2:443', '3.3.3.3:443']);
    });
    test('国家与来源是「且」关系', () {
      final out = filterByFacets(rows, countries: {'US'}, sources: {'洛璃'}, sourceOf: srcOf);
      expect(out.single.ipPort, '3.3.3.3:443');
    });
    test('countFacets 统计行数并保持首次出现顺序', () {
      expect(countFacets(rows.map((r) => nodeCountry(r.node))).keys.toList(), ['US', 'JP']);
      expect(countFacets(rows.map((r) => nodeCountry(r.node))), {'US': 2, 'JP': 1});
      expect(countFacets(rows.map(srcOf)), {'CM': 1, '天诚 Cloudflare': 1, '洛璃': 1});
    });
  });
}
