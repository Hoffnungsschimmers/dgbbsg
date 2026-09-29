import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';

void main() {
  const kConfigJson = 'app_config_json';

  TestWidgetsFlutterBinding.ensureInitialized();

  test('init with empty storage returns default config', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    expect(repo.current.landingOutputFile, 'addressesapi_top.txt');
    expect(repo.current.guiTheme, 'light');
  });

  test('githubToken and webhookUrl go to SecureKV, not SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureKv();
    final repo = await ConfigRepository.init(secure: secure);

    await repo.save(const AppConfig().copyWith(
      githubToken: 'ghp_secret',
      webhookUrl: 'https://api.telegram.org/bot123:secret/sendMessage',
    ));

    final prefs = await SharedPreferences.getInstance();
    final storedJson = jsonDecode(prefs.getString(kConfigJson)!);
    expect(storedJson.containsKey('GITHUB_TOKEN'), isFalse);
    expect(storedJson.containsKey('WEBHOOK_URL'), isFalse);
    expect(await secure.read('github_token'), 'ghp_secret');
    expect(await secure.read('webhook_url'),
        'https://api.telegram.org/bot123:secret/sendMessage');
  });

  test('secrets load back from SecureKV on init', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureKv()
      ..store['github_token'] = 'ghp_secure'
      ..store['webhook_url'] = 'https://discord.com/api/webhooks/abc';

    final repo = await ConfigRepository.init(secure: secure);
    expect(repo.current.githubToken, 'ghp_secure');
    expect(repo.current.webhookUrl, 'https://discord.com/api/webhooks/abc');
  });

  test('legacy plaintext secrets migrate into SecureKV and are stripped',
      () async {
    SharedPreferences.setMockInitialValues({
      kConfigJson: jsonEncode({
        'GITHUB_TOKEN': 'ghp_legacy',
        'WEBHOOK_URL': 'https://api.telegram.org/botL/legacy',
        'SUB_LATENCY_TOP_N': 50,
      }),
    });
    final secure = InMemorySecureKv();
    final repo = await ConfigRepository.init(secure: secure);

    expect(repo.current.githubToken, 'ghp_legacy');
    expect(await secure.read('github_token'), 'ghp_legacy');
    expect(await secure.read('webhook_url'),
        'https://api.telegram.org/botL/legacy');

    final prefs = await SharedPreferences.getInstance();
    final storedJson = jsonDecode(prefs.getString(kConfigJson)!);
    expect(storedJson.containsKey('GITHUB_TOKEN'), isFalse);
    expect(storedJson.containsKey('WEBHOOK_URL'), isFalse);
  });

  test('clearing a secret deletes the SecureKV entry', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = InMemorySecureKv()..store['github_token'] = 'ghp_x';
    final repo = await ConfigRepository.init(secure: secure);

    await repo.save(const AppConfig().copyWith(githubToken: ''));

    expect(await secure.read('github_token'), isNull);
  });

  test('legacy default country UN migrates to empty', () async {
    SharedPreferences.setMockInitialValues({
      kConfigJson: jsonEncode({'SUB_DEFAULT_COUNTRY': 'UN'}),
    });
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    expect(repo.current.subDefaultCountry, '');
  });

  test('migration writes schema version', () async {
    SharedPreferences.setMockInitialValues({
      kConfigJson: jsonEncode({'SUB_DEFAULT_COUNTRY': 'UN'}),
    });
    await ConfigRepository.init(secure: InMemorySecureKv());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('app_config_version'), 1);
  });

  test('versioned config preserves user values', () async {
    SharedPreferences.setMockInitialValues({
      'app_config_version': 1,
      kConfigJson: jsonEncode({
        'LANDING_OUTPUT_FILE': 'custom_top.txt',
        'SUB_DEFAULT_COUNTRY': 'UN',
      }),
    });
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    expect(repo.current.landingOutputFile, 'custom_top.txt');
    // 已有版本标记：不再改写用户值（UN 保持不变）。
    expect(repo.current.subDefaultCountry, 'UN');
  });
}
