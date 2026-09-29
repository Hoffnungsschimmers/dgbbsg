import 'package:cfnb_app/core/net/endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEndpoint', () {
    test('parses ipv4', () {
      final r = parseEndpoint('1.2.3.4:443#US');
      expect(r, isNotNull);
      expect(r!.$1, '1.2.3.4');
      expect(r.$2, 443);
    });
    test('parses ipv6 bracket format', () {
      final r = parseEndpoint('[2001:db8::1]:443#US');
      expect(r, isNotNull);
      expect(r!.$1, '2001:db8::1');
      expect(r.$2, 443);
    });
    test('parses ipv6 bare format', () {
      final r = parseEndpoint('2606:4700:9ad1::c1e2:45b7:2096#HK');
      expect(r, isNotNull);
      expect(r!.$1, '2606:4700:9ad1::c1e2:45b7');
      expect(r.$2, 2096);
    });
    test('rejects bad port', () {
      expect(parseEndpoint('1.2.3.4:99999#US'), isNull);
      expect(parseEndpoint('notanode'), isNull);
    });
    test('parses domain with space-separated source', () {
      final r = parseEndpoint('example.com:2096# 洛璃');
      expect(r, isNotNull);
      expect(r!.$1, 'example.com');
      expect(r.$2, 2096);
    });
    test('parses node with space-separated source after #country', () {
      final r = parseEndpoint('1.2.3.4:443#US CM');
      expect(r, isNotNull);
      expect(r!.$1, '1.2.3.4');
      expect(r.$2, 443);
    });
  });

  group('nodeCountry', () {
    test('extracts country code from node string', () {
      expect(nodeCountry('1.2.3.4:443#JP CM'), 'JP');
      expect(nodeCountry('1.2.3.4:443# 洛璃'), '');
      expect(nodeCountry('1.2.3.4:443'), '');
    });
  });

  group('findCcSourceSep', () {
    test('space and @ separators', () {
      expect(findCcSourceSep('US CM'), 2);
      expect(findCcSourceSep('US@CM'), 2);
      expect(findCcSourceSep('US'), -1);
    });
  });

  group('applyRealLanding', () {
    test('replaces country code keeping source', () {
      expect(
        applyRealLanding('1.2.3.4:443#CN CM', {'1.2.3.4': 'SG'}),
        '1.2.3.4:443#SG CM',
      );
    });
    test('leaves node untouched without mapping', () {
      expect(
        applyRealLanding('1.2.3.4:443#CN CM', {}),
        '1.2.3.4:443#CN CM',
      );
      expect(
        applyRealLanding('1.2.3.4:443#CN CM', {'9.9.9.9': 'SG'}),
        '1.2.3.4:443#CN CM',
      );
    });
    test('覆盖国家码时保留来源名与原始备注', () {
      expect(
        applyRealLanding('1.2.3.4:443#CN 麒麟 美国 洛杉矶 01', {'1.2.3.4': 'SG'}),
        '1.2.3.4:443#SG 麒麟 美国 洛杉矶 01',
      );
      expect(nodeCountry('1.2.3.4:443#US 麒麟 美国 01'), 'US');
    });
  });

}
