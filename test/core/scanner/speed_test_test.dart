import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/core/scanner/speed_test.dart';

void main() {
  group('SpeedTestResult', () {
    test('success returns true when error is null', () {
      const result = SpeedTestResult(
        ip: '1.2.3.4',
        port: 8080,
        speedMBps: 10.0,
        bytesDownloaded: 1024,
        duration: Duration(seconds: 1),
      );
      expect(result.success, isTrue);
    });

    test('success returns false when error is not null', () {
      const result = SpeedTestResult(
        ip: '1.2.3.4',
        port: 8080,
        speedMBps: 0,
        bytesDownloaded: 0,
        duration: Duration.zero,
        error: 'Connection refused',
      );
      expect(result.success, isFalse);
    });

    test('fields are accessible with expected types', () {
      const result = SpeedTestResult(
        ip: '10.0.0.1',
        port: 9090,
        speedMBps: 5.5,
        bytesDownloaded: 2048,
        duration: Duration(milliseconds: 500),
        error: null,
      );
      expect(result.ip, isA<String>());
      expect(result.port, isA<int>());
      expect(result.speedMBps, isA<double>());
      expect(result.bytesDownloaded, isA<int>());
      expect(result.duration, isA<Duration>());
      expect(result.error, isNull);
      expect(result.ip, '10.0.0.1');
      expect(result.port, 9090);
      expect(result.speedMBps, 5.5);
      expect(result.bytesDownloaded, 2048);
    });
  });

  group('speedTestSources', () {
    test('has at least 2 entries', () {
      expect(speedTestSources.length, greaterThanOrEqualTo(2));
    });

    test('each source has non-empty name and url', () {
      for (final source in speedTestSources) {
        expect(source.name, isNotEmpty);
        expect(source.url, isNotEmpty);
      }
    });
  });

  group('SpeedTester.testSingle', () {
    test('returns error result for unreachable IP instead of throwing', () async {
      final result = await SpeedTester.testSingle(
        '192.0.2.1', // TEST-NET address, guaranteed unreachable
        12345,
        sourceUrl: 'http://example.com',
        timeout: const Duration(seconds: 3),
      );
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.speedMBps, 0);
      expect(result.bytesDownloaded, 0);
    });
  });
}
