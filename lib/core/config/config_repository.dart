import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'secure_kv.dart';

/// 配置持久化仓库。内存持有当前 [AppConfig]（单例语义）。
/// 启动时从 shared_preferences 读取；不存在则用默认值。旧键忽略，向后兼容。
/// GitHub Token / Webhook URL 属敏感密钥，单独经 [SecureKV] 安全存储，
/// 不写入 SharedPreferences 明文 JSON（旧版本明文值在启动时一次性迁移）。
class ConfigRepository {
  AppConfig _config;
  final SharedPreferences _prefs;
  final SecureKV _secure;

  ConfigRepository._(this._config, this._prefs, this._secure);

  static const _kConfigJson = 'app_config_json';
  static const _kSchemaVersion = 'app_config_version';
  static const _currentSchemaVersion = 1;
  static const _kGithubToken = 'github_token';
  static const _kWebhookUrl = 'webhook_url';
  static const _kWebdavPassword = 'webdav_password';

  static Future<ConfigRepository> init({SecureKV? secure}) async {
    final prefs = await SharedPreferences.getInstance();
    final secureKv = secure ?? const SecureStorageKv();
    final jsonStr = prefs.getString(_kConfigJson);
    final Map<String, dynamic> data = jsonStr != null
        ? (jsonDecode(jsonStr) as Map<String, dynamic>)
        : <String, dynamic>{};
    var config = data.isNotEmpty ? AppConfig.fromJson(data) : const AppConfig();
    var dirty = false;
    final storedVersion = prefs.getInt(_kSchemaVersion) ?? 0;

    // 一次性历史迁移：仅在没有版本标记的旧配置上执行。
    // 带版本标记后不再改写用户值（subLatencyTopN=0 表示全部保留等）。
    if (storedVersion < _currentSchemaVersion) {
      // 迁移：旧默认国家 UN 视为未配置，改为空串（由节点名国家码决定）。
      if (config.subDefaultCountry.toUpperCase() == 'UN') {
        config = config.copyWith(subDefaultCountry: '');
        dirty = true;
      }
      // 旧默认 2.0s 超时过短，统一为 3.0s。
      if (config.subLatencyTimeout == 2.0) {
        config = config.copyWith(subLatencyTimeout: 3.0);
        dirty = true;
      }
      // 旧默认 maxMs=0（旧版语义不同）统一为推荐值 300。
      if (config.subLatencyMaxMs == 0) {
        config = config.copyWith(subLatencyMaxMs: 300);
        dirty = true;
      }
      // 迁移：旧配置若 subLatencyTopN 为 0（旧默认=全部保留），改为推荐值 50。
      if (config.subLatencyTopN == 0) {
        config = config.copyWith(subLatencyTopN: 50);
        dirty = true;
      }
    }

    // 密钥迁移：优先读取安全存储；旧版本明文 JSON 中的密钥值一次性搬入
    // 安全存储（随后重写 JSON 时 toJson 已不含密钥，明文自动清除）。
    final secureToken = await secureKv.read(_kGithubToken);
    final secureWebhook = await secureKv.read(_kWebhookUrl);
    final secureWebdavPass = await secureKv.read(_kWebdavPassword);
    if (secureToken != null || secureWebhook != null || secureWebdavPass != null) {
      config = config.copyWith(
        githubToken: secureToken ?? config.githubToken,
        webhookUrl: secureWebhook ?? config.webhookUrl,
        webdavPassword: secureWebdavPass ?? config.webdavPassword,
      );
    }
    if (secureToken == null && config.githubToken.isNotEmpty) {
      await secureKv.write(_kGithubToken, config.githubToken);
      dirty = true;
    }
    if (secureWebhook == null && config.webhookUrl.isNotEmpty) {
      await secureKv.write(_kWebhookUrl, config.webhookUrl);
      dirty = true;
    }
    if (secureWebdavPass == null && config.webdavPassword.isNotEmpty) {
      await secureKv.write(_kWebdavPassword, config.webdavPassword);
      dirty = true;
    }

    if (dirty) {
      await prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
    }
    if (storedVersion < _currentSchemaVersion) {
      await prefs.setInt(_kSchemaVersion, _currentSchemaVersion);
    }

    return ConfigRepository._(config, prefs, secureKv);
  }

  AppConfig get current => _config;

  /// 立即更新内存中的配置（不写磁盘）。
  /// 用于 UI 输入时即时同步，防抖后再持久化。
  void updateInMemory(AppConfig config) {
    _config = config;
  }

  /// 持久化：密钥写安全存储，其余写 SharedPreferences 并更新内存。
  Future<void> save(AppConfig config) async {
    _config = config;
    if (config.githubToken.isNotEmpty) {
      await _secure.write(_kGithubToken, config.githubToken);
    } else {
      await _secure.delete(_kGithubToken);
    }
    if (config.webhookUrl.isNotEmpty) {
      await _secure.write(_kWebhookUrl, config.webhookUrl);
    } else {
      await _secure.delete(_kWebhookUrl);
    }
    if (config.webdavPassword.isNotEmpty) {
      await _secure.write(_kWebdavPassword, config.webdavPassword);
    } else {
      await _secure.delete(_kWebdavPassword);
    }
    await _prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
  }

  List<String> validateCurrent() => _config.validate();
}
