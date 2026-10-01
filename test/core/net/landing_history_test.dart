import 'dart:io';

import 'package:cfnb_app/core/net/landing_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appendLandingRound', () {
    test('首次观测写入，egress 一并记录', () {
      final h = appendLandingRound({},
          at: '2026-09-29 20:00:00',
          results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')},
          egressIp: '203.0.113.7');
      final list = h['1.1.1.1']!;
      expect(list.single.at, '2026-09-29 20:00:00');
      expect(list.single.colo, 'HKG');
      expect(list.single.cc, 'HK');
      expect(list.single.egressIp, '203.0.113.7');
    });

    test('与上一条完全相同时不追加（自动更新不会灌满重复项）', () {
      var h = appendLandingRound({},
          at: '2026-09-29 20:00:00', results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')});
      h = appendLandingRound(h,
          at: '2026-09-29 21:00:00', results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')});
      expect(h['1.1.1.1'], hasLength(1));
      expect(h['1.1.1.1']!.single.at, '2026-09-29 20:00:00');
    });

    test('落地变化时追加，且新的在前', () {
      var h = appendLandingRound({},
          at: '2026-09-29 20:00:00',
          results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')},
          egressIp: '家宽');
      h = appendLandingRound(h,
          at: '2026-09-29 21:00:00',
          results: {'1.1.1.1': (colo: 'LAX', cc: 'US')},
          egressIp: '节点');
      final list = h['1.1.1.1']!;
      expect(list.length, 2);
      expect(list.first.at, '2026-09-29 21:00:00');
      expect(list.first.colo, 'LAX');
      expect(list.last.egressIp, '家宽');
    });

    test('每个 IP 裁剪到上限条数', () {
      var h = <String, List<LandingObservation>>{};
      for (var i = 0; i < landingHistoryMaxPerIp + 5; i++) {
        h = appendLandingRound(h,
            at: '2026-09-29 20:00:00',
            results: {'1.1.1.1': (colo: 'C$i', cc: 'HK')});
      }
      expect(h['1.1.1.1'], hasLength(landingHistoryMaxPerIp));
      // 最新的一条留在最前
      expect(h['1.1.1.1']!.first.colo, 'C${landingHistoryMaxPerIp + 4}');
    });

    test('不修改传入的历史表', () {
      final original = appendLandingRound({},
          at: '2026-09-29 20:00:00', results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')});
      final snapshotLength = original['1.1.1.1']!.length;
      appendLandingRound(original,
          at: '2026-09-29 21:00:00', results: {'1.1.1.1': (colo: 'LAX', cc: 'US')});
      expect(original['1.1.1.1']!, hasLength(snapshotLength));
    });
  });

  group('encode / parse', () {
    test('往返一致', () {
      final h = appendLandingRound({},
          at: '2026-09-29 20:00:00',
          results: {'1.1.1.1': (colo: 'HKG', cc: 'HK'), '2.2.2.2': (colo: 'LAX', cc: 'US')},
          egressIp: '203.0.113.7');
      final back = parseLandingHistory(encodeLandingHistory(h));
      expect(back.keys.toSet(), {'1.1.1.1', '2.2.2.2'});
      expect(back['2.2.2.2']!.single.colo, 'LAX');
      expect(back['2.2.2.2']!.single.egressIp, '203.0.113.7');
    });

    test('损坏内容按空表处理，不抛异常', () {
      expect(parseLandingHistory('{不是 json'), isEmpty);
      expect(parseLandingHistory(''), isEmpty);
      expect(parseLandingHistory('[1,2]'), isEmpty);
    });

    test('跳过结构不符的条目', () {
      final h = parseLandingHistory('{"1.1.1.1": "nope", "2.2.2.2": [{"colo":"HKG"}]}');
      expect(h.containsKey('1.1.1.1'), isFalse);
      expect(h['2.2.2.2']!.single.colo, 'HKG');
    });
  });

  group('快照与裁剪', () {
    test('landingStampFor 生成可排序的文件名片段', () {
      expect(landingStampFor('2026-09-29 20:55:01'), '2026-09-29-20-55-01');
    });

    test('写回前快照内容一致，超出保留数量的旧快照被删除', () {
      final dir = Directory.systemTemp.createTempSync('cfnb_lh');
      addTearDown(() => dir.deleteSync(recursive: true));
      final current = File('${dir.path}${Platform.pathSeparator}addressesapi_top.txt')
        ..writeAsStringSync('1.1.1.1:443#HK 麒麟 香港 01\n');

      final snap = snapshotLandingOutput(current, dir, '2026-09-29 20:55:01');
      expect(snap, isNotNull);
      expect(snap!.readAsStringSync(), current.readAsStringSync());
      expect(snap.uri.pathSegments.last, 'landing_2026-09-29-20-55-01.txt');

      // 结果文件不存在时不产生快照
      expect(
          snapshotLandingOutput(
              File('${dir.path}${Platform.pathSeparator}missing.txt'), dir, '2026-09-29 21:00:00'),
          isNull);
    });

    test('recordLandingRound 先读后写，不覆盖既有历史', () async {
      final dir = Directory.systemTemp.createTempSync('cfnb_rec');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}${Platform.pathSeparator}landing_history.json');

      await recordLandingRound(f,
          at: '2026-09-29 20:00:00',
          results: {'1.1.1.1': (colo: 'HKG', cc: 'HK')},
          egressIp: '9.9.9.9');
      await recordLandingRound(f,
          at: '2026-09-29 21:00:00',
          results: {'2.2.2.2': (colo: 'LAX', cc: 'US')},
          egressIp: '8.8.8.8');

      final h = parseLandingHistory(await f.readAsString());
      expect(h.keys.toSet(), {'1.1.1.1', '2.2.2.2'});
      expect(h['1.1.1.1']!.single.egressIp, '9.9.9.9');
      expect(h['2.2.2.2']!.single.colo, 'LAX');
    });

    test('prune 只留最近 landingSnapshotKeep 份', () {
      final dir = Directory.systemTemp.createTempSync('cfnb_lh_prune');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < landingSnapshotKeep + 7; i++) {
        File('${dir.path}${Platform.pathSeparator}landing_2026-01-01-00-00-$i.txt')
            .writeAsStringSync('x');
      }
      // 无关文件不受影响
      File('${dir.path}${Platform.pathSeparator}keep_me.txt').writeAsStringSync('x');

      final removed = pruneLandingSnapshots(dir);
      expect(removed, 7);
      expect(dir.listSync().where((e) => e.path.endsWith('.txt')),
          hasLength(landingSnapshotKeep + 1)); // +1 = keep_me.txt
    });
  });
}
