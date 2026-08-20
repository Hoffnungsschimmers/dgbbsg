import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseResultLines', () {
    test('parses ip.txt with speed and latency', () {
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
  });
}
