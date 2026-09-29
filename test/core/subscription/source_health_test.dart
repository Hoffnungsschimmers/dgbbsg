import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cfnb_app/core/subscription/source_health.dart';

void main() {
  group('updateFailureStreaks', () {
    test('失败累加、成功清零、新失败从 1 开始', () {
      final next = updateFailureStreaks({'CM': 1, 'IDK': 2},
          allSources: ['CM', 'IDK', '洛璃'], failed: {'CM'});
      expect(next, {'CM': 2});
      expect(updateFailureStreaks({}, allSources: ['A'], failed: {'A'}), {'A': 1});
    });

    test('移出配置的源不再保留计数', () {
      expect(updateFailureStreaks({'GONE': 5}, allSources: ['A'], failed: {}), isEmpty);
    });
  });

  group('sourcesCrossedThreshold', () {
    test('只在刚好达到阈值那一轮返回', () {
      expect(sourcesCrossedThreshold({'CM': 2}, {'CM': 3}), ['CM']);
      expect(sourcesCrossedThreshold({'CM': 3}, {'CM': 4}), isEmpty);
    });

    test('多个来源按名字排序，阈值可覆盖', () {
      expect(sourcesCrossedThreshold({}, {'洛璃': 3, 'CM': 3}), ['CM', '洛璃']);
      expect(sourcesCrossedThreshold({}, {'CM': 2}, threshold: 2), ['CM']);
    });
  });

  group('SourceHealth 持久化', () {
    test('读写往返；缺键返回空表', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(SourceHealth.fromPrefs(prefs), isEmpty);
      await SourceHealth.saveToPrefs(prefs, {'CM': 2, 'IDK': 1});
      expect(SourceHealth.fromPrefs(prefs), {'CM': 2, 'IDK': 1});
    });

    test('内容损坏时返回空表而不抛异常', () async {
      SharedPreferences.setMockInitialValues({'flutter.source_health_json': '{不是 json'});
      final prefs = await SharedPreferences.getInstance();
      expect(SourceHealth.fromPrefs(prefs), isEmpty);
    });

    test('计数存在独立键，不随 app_config_json 一起被备份/恢复覆盖', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.source_health_json': jsonEncode({'CM': 9}),
        'flutter.app_config_json': jsonEncode({'GITHUB_REPO': 'o/r'}),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(SourceHealth.fromPrefs(prefs), {'CM': 9});
      // 健康度写入不会碰配置键
      await SourceHealth.saveToPrefs(prefs, {'CM': 10});
      final restored = jsonDecode(prefs.getString('app_config_json')!) as Map<String, dynamic>;
      expect(restored['GITHUB_REPO'], 'o/r');
      expect(SourceHealth.fromPrefs(prefs), {'CM': 10});
    });
  });

  group('连续失败告警时序', () {
    test('第三轮触发一次，第四轮不重复', () {
      var prev = <String, int>{};
      final alerts = <List<String>>[];
      for (var round = 0; round < 4; round++) {
        final next = updateFailureStreaks(prev, allSources: ['CM', 'IDK'], failed: {'CM'});
        alerts.add(sourcesCrossedThreshold(prev, next));
        prev = next;
      }
      expect(alerts.map((e) => e.join()).toList(), ['', '', 'CM', '']);
    });

    test('中途恢复后重新从 1 计数', () {
      var prev = updateFailureStreaks({}, allSources: ['CM'], failed: {'CM'});
      prev = updateFailureStreaks(prev, allSources: ['CM'], failed: {'CM'});
      prev = updateFailureStreaks(prev, allSources: ['CM'], failed: {});
      expect(updateFailureStreaks(prev, allSources: ['CM'], failed: {'CM'}), {'CM': 1});
    });

    test('同名任务有一项成功即不算失败（多个未打标签链接都叫 url）', () {
      const ok = {'url'};
      const failed = {'url'};
      final effective = failed.difference(ok);
      expect(updateFailureStreaks({'url': 2}, allSources: {'url'}, failed: effective), isEmpty);
    });
  });
}
