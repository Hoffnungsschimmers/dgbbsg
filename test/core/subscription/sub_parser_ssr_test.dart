import 'dart:convert';

import 'package:cfnb_app/core/subscription/sub_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSsr', () {
    test('parses basic SSR base64-encoded URI', () {
      // Inner: 1.2.3.4:443:origin:aes-256-cfb:plain:dGVzdHBhc3M=
      final b64 = base64Encode(
        utf8.encode('1.2.3.4:443:origin:aes-256-cfb:plain:dGVzdHBhc3M='),
      );
      final r = SubParser.parseSsr('ssr://$b64');
      expect(r, isNotNull);
      expect(r!.host, '1.2.3.4');
      expect(r.port, 443);
      expect(r.name, '');
    });

    test('parses SSR with remarks param', () {
      // remarks = base64("测试节点") = 5rWL6K+V6IqC54K5
      final remarksB64 = base64Encode(utf8.encode('测试节点'));
      final inner =
          '1.2.3.4:443:origin:aes-256-cfb:plain:dGVzdHBhc3M=/?remarks=$remarksB64';
      final b64 = base64Encode(utf8.encode(inner));
      final r = SubParser.parseSsr('ssr://$b64');
      expect(r, isNotNull);
      expect(r!.host, '1.2.3.4');
      expect(r.port, 443);
      expect(r.name, '测试节点');
    });

    test('parses SSR with group fallback when no remarks', () {
      final groupB64 = base64Encode(utf8.encode('MyGroup'));
      final inner =
          '10.0.0.1:8388:auth_aes128_md5:rc4:tls1.2_ticket_auth:aGVsbG8=/?group=$groupB64';
      final b64 = base64Encode(utf8.encode(inner));
      final r = SubParser.parseSsr('ssr://$b64');
      expect(r, isNotNull);
      expect(r!.host, '10.0.0.1');
      expect(r.port, 8388);
      expect(r.name, 'MyGroup');
    });

    test('returns null for invalid SSR URI', () {
      expect(SubParser.parseSsr('ssr://not-valid-base64!!!'), isNull);
    });

    test('returns null for SSR with missing segments', () {
      // Only 3 colon-separated segments instead of 6
      final b64 = base64Encode(utf8.encode('1.2.3.4:443:origin'));
      expect(SubParser.parseSsr('ssr://$b64'), isNull);
    });

    test('returns null for SSR with zero port', () {
      final b64 = base64Encode(
        utf8.encode('1.2.3.4:0:origin:aes-256-cfb:plain:dGVzdHBhc3M='),
      );
      expect(SubParser.parseSsr('ssr://$b64'), isNull);
    });
  });

  group('parseTrojan', () {
    test('parses trojan link with fragment name', () {
      final r = SubParser.parseTrojan('trojan://pass@5.6.7.8:8443#CM');
      expect(r, isNotNull);
      expect(r!.host, '5.6.7.8');
      expect(r.port, 8443);
      expect(r.name, 'CM');
    });

    test('parses trojan link with remarks query param', () {
      final r =
          SubParser.parseTrojan('trojan://pass@5.6.7.8:8443?remarks=hello');
      expect(r, isNotNull);
      expect(r!.name, 'hello');
    });
  });

  group('parseSubscriptionLinks', () {
    test('includes SSR nodes in results', () {
      final remarksB64 = base64Encode(utf8.encode('SSR节点'));
      final ssrInner =
          '1.2.3.4:443:origin:aes-256-cfb:plain:dGVzdHBhc3M=/?remarks=$remarksB64';
      final ssrB64 = base64Encode(utf8.encode(ssrInner));

      final text = '''
vless://uuid@10.0.0.1:443#VLESS
ssr://$ssrB64
trojan://pass@5.6.7.8:8443#TR
not-a-link
''';
      final results = SubParser.parseSubscriptionLinks(text);
      expect(results.length, 3);

      final hosts = results.map((r) => r.host).toList();
      expect(hosts, contains('10.0.0.1'));
      expect(hosts, contains('1.2.3.4'));
      expect(hosts, contains('5.6.7.8'));

      final ssrResult = results.firstWhere((r) => r.host == '1.2.3.4');
      expect(ssrResult.port, 443);
      expect(ssrResult.name, 'SSR节点');
    });
  });
}
