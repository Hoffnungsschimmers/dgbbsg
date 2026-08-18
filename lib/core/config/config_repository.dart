import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// 配置持久化仓库。内存持有当前 [AppConfig]（单例语义）。
/// 启动时从 shared_preferences 读取；不存在则用默认值。旧键忽略，向后兼容。
class ConfigRepository {
  AppConfig _config;
  final SharedPreferences _prefs;

  ConfigRepository._(this._config, this._prefs);

  static Future<ConfigRepository> init() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kConfigJson);
    final Map<String, dynamic> data = jsonStr != null
        ? (jsonDecode(jsonStr) as Map<String, dynamic>)
        : <String, dynamic>{};
    var config = data.isNotEmpty ? AppConfig.fromJson(data) : const AppConfig();
    var dirty = false;

    // 迁移：旧默认国家 UN 视为未配置，改为空串（由节点名国家码决定）。
    if (config.subDefaultCountry.toUpperCase() == 'UN') {
      config = config.copyWith(subDefaultCountry: '');
      dirty = true;
    }

    if (config.subLatencyTimeout == 2.0) {
      config = config.copyWith(subLatencyTimeout: 3.0);
      dirty = true;
    }
    if (config.subLatencyMaxMs == 0) {
      config = config.copyWith(subLatencyMaxMs: 300);
      dirty = true;
    }

    // 迁移：旧配置若 subLatencyTopN 为 0（旧默认=全部保留），改为推荐值 50。
    if (config.subLatencyTopN == 0) {
      config = config.copyWith(subLatencyTopN: 50);
      dirty = true;
    }

    if (dirty) {
      await prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
    }

    return ConfigRepository._(config, prefs);
  }

  static const _kConfigJson = 'app_config_json';

  AppConfig get current => _config;

  /// 立即更新内存中的配置（不写磁盘）。
  /// 用于 UI 输入时即时同步，防抖后再持久化。
  void updateInMemory(AppConfig config) {
    _config = config;
  }

  /// 持久化到 SharedPreferences 并更新内存。
  Future<void> save(AppConfig config) async {
    _config = config;
    await _prefs.setString(_kConfigJson, jsonEncode(config.toJson()));
  }


  List<String> validateCurrent() => _config.validate();
}
