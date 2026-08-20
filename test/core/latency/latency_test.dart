import 'dart:io';

import 'package:cfnb_app/core/latency/latency_filter.dart';
import 'package:cfnb_app/core/latency/latency_prober.dart';
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

  group('latencyProbeAll', () {
    test('orders succeeded before failed, ascending latency', () async {
      // 注入假探测：按 ip 末位决定延迟，特定 ip 超时
      Future<(double?, double?, int)> fake(String ip, int port, Duration _, {int probes = 1, bool Function()? isCancelled}) async {
        if (ip.endsWith('.9')) return (null, null, 0); // 超时
        final last = int.parse(ip.split('.').last);
        return (last.toDouble(), 0.0, 1);
      }
      final nodes = [
        '10.0.0.3:443#US',
        '10.0.0.1:443#US',
        '10.0.0.9:443#US', // 失败
      ];
      final (ordered, tested, connected) = await latencyProbeAll(
        nodes,
        timeout: const Duration(seconds: 2),
        workers: 5,
        probe: fake,
      );
      expect(tested, 3);
      expect(connected, 2);
      expect(ordered.first.latencyMs, 1.0);
      expect(ordered.last.latencyMs, isNull);
    });

    test('respects worker semaphore (no overflow)', () async {
      var concurrent = 0;
      var maxConcurrent = 0;
      Future<(double?, double?, int)> fake(String ip, int port, Duration _, {int probes = 1, bool Function()? isCancelled}) async {
        concurrent++;
        maxConcurrent = maxConcurrent < concurrent ? concurrent : maxConcurrent;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        concurrent--;
        return (1.0, 0.0, 1);
      }
      final nodes = List.generate(20, (i) => '10.0.0.$i:443#US');
      await latencyProbeAll(nodes, timeout: const Duration(seconds: 2), workers: 4, probe: fake);
      expect(maxConcurrent, lessThanOrEqualTo(4));
    });
  });

  group('LatencyFilter.run', () {
    test('writes output and json with latency cutoff', () async {
      Future<(double?, double?, int)> fake(String ip, int port, Duration _, {int probes = 1, bool Function()? isCancelled}) async {
        if (ip.endsWith('.9')) return (null, null, 0);
        return (int.parse(ip.split('.').last).toDouble(), 0.0, 1);
      }
      final dir = await Directory.systemTemp.createTemp('cfnb_lat_');
      final out = '${dir.path}/addressesapi_top.txt';
      final nodes = [
        '10.0.0.5:443#US CM',
        '10.0.0.2:443#US CM',
        '10.0.0.9:443#US CM',
      ];
      final (kept, tested, connected) = await LatencyFilter.run(
        nodes: nodes,
        outputFile: out,
        latencyMaxMs: 1000,
        timeout: const Duration(seconds: 2),
        workers: 5,
        nodeSource: {'10.0.0.5:443#US CM': 'CM'},
        probe: fake,
      );
      expect(tested, 3);
      expect(connected, 2);
      expect(kept.length, 2);
      final content = await File(out).readAsString();
      expect(content, contains('ms'));
      final json = await File('$out.json').readAsString();
      expect(json, contains('"connected":2'));
      await dir.delete(recursive: true);
    });

    test('keeps top N by quality, ranks them', () async {
      Future<(double?, double?, int)> fake(String ip, int port, Duration _, {int probes = 1, bool Function()? isCancelled}) async {
        return (10.0, 0.0, 1);
      }
      final dir = await Directory.systemTemp.createTemp('cfnb_lat_');
      final out = '${dir.path}/top.txt';
      final nodes = List.generate(50, (i) => '10.0.0.$i:443#US');
      final (kept, tested, connected) = await LatencyFilter.run(
        nodes: nodes,
        outputFile: out,
        latencyMaxMs: 1000,
        timeout: const Duration(seconds: 2),
        workers: 5,
        topN: 10,
        probe: fake,
      );
      expect(tested, 50);
      expect(connected, 50);
      expect(kept.length, 10);
      final content = await File(out).readAsString();
      // 输出按延迟升序（前 10 名），无序号
      final lines = content.split('\n').where((l) => l.startsWith('10.0.0.')).toList();
      expect(lines.length, 10);
      // 不含序号标记
      expect(content, isNot(contains('#1 ')));
      final json = await File('$out.json').readAsString();
      expect(json, contains('"rank":1'));
      await dir.delete(recursive: true);
    });
  });
}
