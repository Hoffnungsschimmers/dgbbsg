import 'package:cfnb_app/core/scanner/cf_range_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CfRangeScanner.fetchSubnets', () {
    test('returns non-empty subnet list (API or fallback)', () async {
      final subnets = await CfRangeScanner.fetchSubnets();
      expect(subnets, isNotEmpty);
      for (final s in subnets) {
        expect(s, contains('/'));
      }
    });
  });

  group('CfRangeScanner.generateIPs', () {
    test('generates valid IPs', () async {
      final ips = await CfRangeScanner.generateIPs();
      expect(ips, isNotEmpty);
      for (final ip in ips) {
        expect(ip, isNotEmpty);
        expect(ip, contains('.'));
      }
    });
  });
}
