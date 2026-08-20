import 'dart:convert';

import 'package:cfnb_app/core/subscription/sub_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('b64DecodeLoose', () {
    test('decodes standard base64', () {
      // base64("hello") = aGVsbG8=
      expect(SubParser.b64DecodeLoose('aGVsbG8='), 'hello');
    });
    test('decodes without padding', () {
      expect(SubParser.b64DecodeLoose('aGVsbG8'), 'hello');
    });
    test('returns null on empty', () {
      expect(SubParser.b64DecodeLoose(''), isNull);
    });
  });

  group('parseUriStyle', () {
    test('parses vless with fragment name', () {
      final r = SubParser.parseUriStyle('vless://uuid@1.2.3.4:443?type=ws#%E6%97%A5%E6%9C%AC');
      expect(r, isNotNull);
      expect(r!.host, '1.2.3.4');
      expect(r.port, 443);
      expect(r.name, '日本');
    });
    test('parses trojan', () {
      final r = SubParser.parseUriStyle('trojan://pass@5.6.7.8:8443#CM');
      expect(r!.host, '5.6.7.8');
      expect(r.port, 8443);
      expect(r.name, 'CM');
    });
    test('falls back to query remarks', () {
      final r = SubParser.parseUriStyle('vless://uuid@1.2.3.4:443?remarks=hello');
      expect(r!.name, 'hello');
    });
  });

  group('parseVmess', () {
    test('parses base64 json', () {
      final json = '{"add":"9.9.9.9","port":443,"ps":"测试节点"}';
      final b64 = base64Encode(utf8.encode(json));
      final r = SubParser.parseVmess('vmess://$b64');
      expect(r, isNotNull);
      expect(r!.host, '9.9.9.9');
      expect(r.port, 443);
      expect(r.name, '测试节点');
    });
  });

  group('parseSubscriptionLinks', () {
    test('parses mixed links', () {
      final text = '''
vless://uuid@1.2.3.4:443#JP
vmess://${base64Encode(utf8.encode('{"add":"9.9.9.9","port":443,"ps":"X"}'))}
trojan://p@5.6.7.8:8443#CM
not-a-link
''';
      final results = SubParser.parseSubscriptionLinks(text);
      expect(results.length, 3);
      expect(results.map((r) => r.host), contains('1.2.3.4'));
      expect(results.map((r) => r.host), contains('9.9.9.9'));
    });
  });
}
