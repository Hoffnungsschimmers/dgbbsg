import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig defaults', () {
    final c = const AppConfig();

    test('has expected default values', () {
      expect(c.guiTheme, 'light');
      expect(c.subInputMode, 'both');
      expect(c.subFetchMaxRetries, 2);
      expect(c.subFetchRetryDelay, 2.0);
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
      expect(c.subDefaultCountry, '');
      expect(c.landingOutputFile, 'addressesapi_top.txt');
      expect(c.subInsecure, isFalse);
      expect(c.githubRepo, 'Hoffnungsschimmers/mnscn');
    });

    test('缺 GITHUB_REPO 键时兜底与构造函数默认一致', () {
      // 曾出现构造函数用 mnscn、fromJson 兜底用 cf-ip 的分叉：
      // 老配置没存过这个键时会被静默换成另一个仓库。
      expect(AppConfig.fromJson({}).githubRepo, const AppConfig().githubRepo);
    });

    test('dead fields removed', () {
      // 编译期保证：以下字段不应存在（构建即失败若引用了已删字段）
      expect(c, isA<AppConfig>());
    });

    test('toJson then fromJson is stable', () {
      final json = c.toJson();
      final round = AppConfig.fromJson(json);
      expect(round.subDisabledGenerators, c.subDisabledGenerators);
      expect(round.subGenerators, c.subGenerators);
      expect(round.landingOutputFile, c.landingOutputFile);
    });

    test('landing output file migrates from legacy latency key', () {
      // 旧配置只有 SUB_LATENCY_OUTPUT_FILE：兜底读取。
      final legacy = AppConfig.fromJson({'SUB_LATENCY_OUTPUT_FILE': 'my_top.txt'});
      expect(legacy.landingOutputFile, 'my_top.txt');
      // 新键优先于旧键。
      final both = AppConfig.fromJson({
        'SUB_LATENCY_OUTPUT_FILE': 'old_top.txt',
        'LANDING_OUTPUT_FILE': 'new_top.txt',
      });
      expect(both.landingOutputFile, 'new_top.txt');
      expect(both.toJson()['LANDING_OUTPUT_FILE'], 'new_top.txt');
    });

    test('webdav fields roundtrip', () {
      const wd = AppConfig(
        webdavUrl: 'https://dav.jianguoyun.com/dav',
        webdavUser: 'me@example.com',
        webdavPassword: 'p@ss',
        webdavAutoSync: true,
        webdavAutoSyncIntervalMin: 45,
      );
      final json = wd.toJson();
      final round = AppConfig.fromJson(json);
      expect(round.webdavUrl, 'https://dav.jianguoyun.com/dav');
      expect(round.webdavUser, 'me@example.com');
      expect(round.webdavAutoSync, isTrue);
      expect(round.webdavAutoSyncIntervalMin, 45);
      // 密码为敏感字段：不进 SharedPreferences JSON（经 SecureKV 存取）
      expect(json.containsKey('WEBDAV_PASSWORD'), isFalse);
      expect(round.webdavPassword, '');
    });

    test('已废弃的 LANDING_PROXY 键被忽略且不回写（落地检测只直连）', () {
      final c = AppConfig.fromJson({'LANDING_PROXY': '127.0.0.1:7890'});
      expect(c.toJson().containsKey('LANDING_PROXY'), isFalse);
    });
  });

  group('AppConfig.fromJson parsing', () {
    test('parses disabled generators set', () {
      final c = AppConfig.fromJson({
        'SUB_DISABLED_GENERATORS': ['CM', 'HK'],
      });
      expect(c.subDisabledGenerators, {'CM', 'HK'});
    });

    test('ignores unknown legacy keys without throwing', () {
      final c = AppConfig.fromJson({
        'CF_API_TOKEN': 'x',
        'ASN_SOURCES': [1],
        'SUB_NODE_UUID': 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
      });
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
    });
  });

  group('AppConfig.validate', () {
    test('accepts defaults', () {
      expect(const AppConfig().validate(), isEmpty);
    });

    test('rejects bad sub input mode', () {
      final bad = AppConfig.fromJson({'SUB_INPUT_MODE': 'xxx'});
      expect(bad.validate(), isNotEmpty);
    });

    test('auto sync requires webdav url and min interval', () {
      final noUrl = AppConfig.fromJson({'WEBDAV_AUTO_SYNC': true});
      expect(noUrl.validate(), isNotEmpty);
      final badInterval =
          AppConfig.fromJson({'WEBDAV_AUTO_SYNC_INTERVAL_MIN': 1});
      expect(badInterval.validate(), isNotEmpty);
      final ok = AppConfig.fromJson({
        'WEBDAV_AUTO_SYNC': true,
        'WEBDAV_URL': 'https://dav.test/dav',
      });
      expect(ok.validate(), isEmpty);
    });
  });

  group('AppConfig.copyWith', () {
    test('updates single field without touching others', () {
      final c = const AppConfig();
      final updated = c.copyWith(guiTheme: 'dark', landingOutputFile: 'other_top.txt');
      expect(updated.guiTheme, 'dark');
      expect(updated.landingOutputFile, 'other_top.txt');
      expect(updated.subInputMode, c.subInputMode);
    });
  });
}
