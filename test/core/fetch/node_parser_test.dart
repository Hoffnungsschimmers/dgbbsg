import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:flutter_test/flutter_test.dart';

NodeParser makeParser() => NodeParser(
      cnToCode: {
        '美国': 'US',
        '中国': 'CN',
        '日本': 'JP',
        '德国': 'DE',
      },
      alpha3ToAlpha2: {
        'USA': 'US',
        'DEU': 'DE',
        'JPN': 'JP',
      },
    );

void main() {
  final parser = makeParser();

  group('extractCountryCode', () {
    test('matches alpha2 directly', () {
      expect(parser.extractCountryCode('US'), 'US');
      expect(parser.extractCountryCode('JP'), 'JP');
    });
    test('matches alpha3', () {
      expect(parser.extractCountryCode('USA'), 'US');
      expect(parser.extractCountryCode('DEU'), 'DE');
    });
    test('matches chinese name', () {
      expect(parser.extractCountryCode('美国'), 'US');
      expect(parser.extractCountryCode('日本'), 'JP');
    });
    test('returns null when unknown', () {
      expect(parser.extractCountryCode('???'), isNull);
    });
  });

  group('splitLabel', () {
    test('标签仅为国家码时备注为空', () {
      expect(parser.splitLabel('US'), (cc: 'US', remark: ''));
    });
    test('国家码后剩余文本作为备注', () {
      expect(parser.splitLabel('US 洛杉矶 01'), (cc: 'US', remark: '洛杉矶 01'));
      expect(parser.splitLabel('US@cm'), (cc: 'US', remark: 'cm'));
    });
    test('中文地区名提取国家码并整串保留为备注', () {
      expect(parser.splitLabel('美国'), (cc: 'US', remark: '美国'));
    });
    test('第二个 # 起的原文并入备注', () {
      expect(parser.splitLabel('CN#湖南长沙-移动'), (cc: 'CN', remark: '湖南长沙-移动'));
    });
    test('无法识别国家码时 cc 为 null、整串作备注', () {
      expect(parser.splitLabel('未知线路'), (cc: null, remark: '未知线路'));
    });
  });

  group('parseTextNodesWithRemark', () {
    test('保留 # 后的原始备注', () {
      expect(
        parser.parseTextNodesWithRemark('1.2.3.4:443#US 洛杉矶 01'),
        [(ipPort: '1.2.3.4:443', cc: 'US', remark: '洛杉矶 01')],
      );
    });
    test('中文标签转国家码并留备注', () {
      expect(
        parser.parseTextNodesWithRemark('1.2.3.4#日本 东京'),
        [(ipPort: '1.2.3.4:443', cc: 'JP', remark: '日本 东京')],
      );
    });
    test('无标签行 cc 与 remark 均为空', () {
      expect(
        parser.parseTextNodesWithRemark('1.2.3.4'),
        [(ipPort: '1.2.3.4:443', cc: '', remark: '')],
      );
    });
    test('IPv6 方括号化后保留备注', () {
      expect(
        parser.parseTextNodesWithRemark('[2606:4700:52::1]:443#US 圣何塞'),
        [(ipPort: '[2606:4700:52::1]:443', cc: 'US', remark: '圣何塞')],
      );
    });
    test('忽略注释行与无国家码可提取的行不丢弃', () {
      expect(parser.parseTextNodesWithRemark('#US 圣何塞'), isEmpty);
      expect(
        parser.parseTextNodesWithRemark('1.2.3.4:443#未知'),
        [(ipPort: '1.2.3.4:443', cc: '', remark: '未知')],
      );
    });
  });

  group('parseTextNodes', () {
    test('parses ip:port#label with country', () {
      final nodes = parser.parseTextNodes('1.2.3.4:443#美国\n');
      expect(nodes, ['1.2.3.4:443#US']);
    });
    test('adds default port 443 for bare ip', () {
      final nodes = parser.parseTextNodes('1.2.3.4#日本');
      expect(nodes, ['1.2.3.4:443#JP']);
    });
    test('skips nodes without recognized country', () {
      final nodes = parser.parseTextNodes('1.2.3.4:443#未知');
      expect(nodes, isEmpty);
    });
    test('ignores comment lines', () {
      final nodes = parser.parseTextNodes('#1.2.3.4:443#US');
      expect(nodes, isEmpty);
    });
    test('parses bare ipv6:port and adds brackets', () {
      final nodes = parser
          .parseTextNodes('2606:4700:8394:b884:22e2:7cb7:25bd:b7da:443#美国');
      expect(
        nodes,
        ['[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#US'],
      );
    });
    test('parses bracketed ipv6:port', () {
      final nodes = parser
          .parseTextNodes('[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#美国');
      expect(
        nodes,
        ['[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#US'],
      );
    });
  });

  group('parseAdaptive', () {
    test('parses JSON list of nodes', () {
      final text = '[{"ip":"1.1.1.1","port":443,"country":"US"}]';
      final nodes = parser.parseAdaptive(text);
      expect(nodes, ['1.1.1.1:443#US']);
    });
    test('falls back to text', () {
      final nodes = parser.parseAdaptive('9.9.9.9:443#DE');
      expect(nodes, ['9.9.9.9:443#DE']);
    });
  });
}
