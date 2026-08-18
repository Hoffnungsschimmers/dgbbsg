import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('measureLatencyMultiPort', () {
    test('returns best (lowest latency) port result', () async {
      // Mock probe: port 443 -> 100ms, port 8443 -> 50ms, port 2096 -> 200ms
      Future<(double?, double?, int)> mockProbe(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        switch (port) {
          case 443:
            return (100.0, 5.0, 1);
          case 8443:
            return (50.0, 2.0, 1);
          case 2096:
            return (200.0, 10.0, 1);
          default:
            return (null, null, 0);
        }
      }

      final (lat, jitter, ok, bestPort) = await measureLatencyMultiPort(
        '1.2.3.4',
        [443, 8443, 2096],
        const Duration(seconds: 2),
        probe: mockProbe,
      );

      expect(lat, 50.0);
      expect(jitter, 2.0);
      expect(ok, 1);
      expect(bestPort, 8443);
    });

    test('returns first best port when multiple ports have same latency', () async {
      Future<(double?, double?, int)> mockProbe(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        if (port == 443) return (100.0, 5.0, 1);
        if (port == 8080) return (50.0, 2.0, 1);
        if (port == 2096) return (50.0, 3.0, 1);
        return (null, null, 0);
      }

      final (lat, jitter, ok, bestPort) = await measureLatencyMultiPort(
        '1.2.3.4',
        [443, 8080, 2096],
        const Duration(seconds: 2),
        probe: mockProbe,
      );

      // Both 8080 and 2096 return 50.0; 8080 is probed first
      expect(lat, 50.0);
      expect(bestPort, 8080);
    });

    test('skips failed ports and picks successful one', () async {
      Future<(double?, double?, int)> mockProbe(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        if (port == 443) return (null, null, 0); // fail
        if (port == 8443) return (null, null, 0); // fail
        if (port == 2096) return (80.0, 1.0, 1);
        return (null, null, 0);
      }

      final (lat, jitter, ok, bestPort) = await measureLatencyMultiPort(
        '1.2.3.4',
        [443, 8443, 2096],
        const Duration(seconds: 2),
        probe: mockProbe,
      );

      expect(lat, 80.0);
      expect(jitter, 1.0);
      expect(ok, 1);
      expect(bestPort, 2096);
    });

    test('returns (null, null, 0, 0) when all ports fail', () async {
      Future<(double?, double?, int)> mockProbe(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        return (null, null, 0);
      }

      final (lat, jitter, ok, bestPort) = await measureLatencyMultiPort(
        '1.2.3.4',
        [443, 8443, 2096],
        const Duration(seconds: 2),
        probe: mockProbe,
      );

      expect(lat, isNull);
      expect(jitter, isNull);
      expect(ok, 0);
      expect(bestPort, 0);
    });

    test('works with single port', () async {
      Future<(double?, double?, int)> mockProbe(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        return (42.0, 1.5, 1);
      }

      final (lat, jitter, ok, bestPort) = await measureLatencyMultiPort(
        '1.2.3.4',
        [443],
        const Duration(seconds: 2),
        probe: mockProbe,
      );

      expect(lat, 42.0);
      expect(jitter, 1.5);
      expect(ok, 1);
      expect(bestPort, 443);
    });
  });

  group('latencyProbeAllMultiPort', () {
    test('delegates to latencyProbeAll when extraPorts is empty', () async {
      Future<(double?, double?, int)> fake(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        final last = int.parse(ip.split('.').last);
        return (last.toDouble(), 0.0, 1);
      }

      final nodes = [
        '10.0.0.3:443#US',
        '10.0.0.1:443#US',
      ];

      final (ordered, tested, connected) = await latencyProbeAllMultiPort(
        nodes,
        timeout: const Duration(seconds: 2),
        workers: 5,
        probe: fake,
      );

      expect(tested, 2);
      expect(connected, 2);
      expect(ordered.first.latencyMs, 1.0);
      expect(ordered.last.latencyMs, 3.0);
    });

    test('probes extra ports and picks best result', () async {
      // Port 443 gives high latency, port 8443 gives low latency
      Future<(double?, double?, int)> fake(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        if (port == 8443) return (10.0, 0.5, 1);
        return (100.0, 5.0, 1); // default for port 443
      }

      final nodes = ['10.0.0.1:443#US'];

      final (ordered, tested, connected) = await latencyProbeAllMultiPort(
        nodes,
        timeout: const Duration(seconds: 2),
        workers: 5,
        extraPorts: [8443],
        probe: fake,
      );

      expect(tested, 1);
      expect(connected, 1);
      // Best latency across ports 443 and 8443 is 10.0
      expect(ordered.first.latencyMs, 10.0);
    });

    test('marks node as failed when all ports fail', () async {
      Future<(double?, double?, int)> fake(
        String ip,
        int port,
        Duration _, {
        int probes = 1,
        bool Function()? isCancelled,
      }) async {
        return (null, null, 0);
      }

      final nodes = ['10.0.0.1:443#US'];

      final (ordered, tested, connected) = await latencyProbeAllMultiPort(
        nodes,
        timeout: const Duration(seconds: 2),
        workers: 5,
        extraPorts: [8443, 2096],
        probe: fake,
      );

      expect(tested, 1);
      expect(connected, 0);
      expect(ordered.first.latencyMs, isNull);
    });
  });
}
