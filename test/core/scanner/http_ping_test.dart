import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:cfnb_app/core/scanner/http_ping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('measureHttpTtfb signature compatibility', () {
    test('has the same signature type as measureLatency (pluggable)', () {
      // Verify that measureHttpTtfb can be assigned to the probe parameter type
      // used by latencyProbeAll. This is a compile-time guarantee expressed as a
      // runtime type check.
      Future<(double?, double?, int)> Function(String, int, Duration, {int probes})
          probe = measureHttpTtfb;
      expect(probe, isNotNull);
    });

    test('can be passed as probe parameter to latencyProbeAll', () {
      // Call latencyProbeAll with measureHttpTtfb as the probe; pass an empty
      // node list so it completes instantly but the type is validated.
      final future = latencyProbeAll(
        [],
        timeout: const Duration(milliseconds: 100),
        workers: 1,
        probe: measureHttpTtfb,
      );
      expect(future, completes);
    });
  });

  group('measureHttpTtfb with unreachable host', () {
    test('returns (null, null, 0) when all probes fail', () async {
      // Use a non-routable IP (RFC 5737 documentation range) to force failure.
      final result = await measureHttpTtfb(
        '192.0.2.1',
        80,
        const Duration(milliseconds: 300),
        probes: 1,
      );
      expect(result.$1, isNull); // latency
      expect(result.$2, isNull); // jitter
      expect(result.$3, 0);      // success count
    });
  });
}
