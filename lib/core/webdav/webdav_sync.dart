import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import 'webdav_client.dart';

/// WebDAV 同步服务：配置与结果文件在云盘与本地之间的备份/恢复。
///
/// - 配置备份为单个 `cfnb_config.json`（含敏感字段，恢复时经 SecureKV 落盘）。
/// - 结果文件按文件名逐个上传/下载（含同名 .json 旁文件）。
class WebDavSync {
  WebDavSync._();

  /// 云盘上的配置文件路径。
  static const configFileName = 'cfnb_config.json';

  /// 组装完整配置 JSON（toJson 不含敏感字段，此处补上用于云盘备份）。
  static Map<String, dynamic> fullConfigJson(AppConfig cfg) {
    final m = cfg.toJson();
    m['GITHUB_TOKEN'] = cfg.githubToken;
    m['WEBHOOK_URL'] = cfg.webhookUrl;
    m['WEBDAV_PASSWORD'] = cfg.webdavPassword;
    return m;
  }

  /// 参与同步的结果文件集合：两个输出文件 + 当前结果文件，各带 .json 旁文件。
  static List<String> resultFileNames(AppConfig cfg, String? currentFile) {
    final names = <String>{};
    if (cfg.subOutputFile.trim().isNotEmpty) {
      names.add(cfg.subOutputFile.trim().split(RegExp(r'[\\/]')).last);
    }
    if (cfg.subLatencyOutputFile.trim().isNotEmpty) {
      names.add(cfg.subLatencyOutputFile.trim().split(RegExp(r'[\\/]')).last);
    }
    if (currentFile != null && currentFile.trim().isNotEmpty) {
      names.add(currentFile.trim().split(RegExp(r'[\\/]')).last);
    }
    final withJson = <String>{};
    for (final n in names) {
      withJson.add(n);
      withJson.add('$n.json');
    }
    final list = withJson.toList();
    list.sort();
    return list;
  }

  /// 备份配置：上传 cfnb_config.json。
  static Future<void> backupConfig(WebDavClient client, AppConfig cfg) async {
    final bytes = utf8.encode(jsonEncode(fullConfigJson(cfg)));
    await client.upload(configFileName, bytes);
  }

  /// 从云盘拉取配置，返回解析后的 [AppConfig]。
  static Future<AppConfig> restoreConfig(WebDavClient client) async {
    final bytes = await client.download(configFileName);
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return AppConfig.fromJson(map);
  }

  /// 备份结果文件：上传本地存在的结果文件，返回成功上传的文件名列表。
  static Future<List<String>> backupResults(
    WebDavClient client,
    String docDir,
    List<String> names,
  ) async {
    final uploaded = <String>[];
    for (final name in names) {
      final f = File(resolveOutputPath(name, docDir));
      if (!f.existsSync()) continue;
      await client.upload(name, await f.readAsBytes());
      uploaded.add(name);
    }
    return uploaded;
  }

  /// 恢复结果文件：下载云盘上存在的结果文件并写回本地，返回恢复的文件名列表。
  /// 云盘上不存在的文件（404）跳过。
  static Future<List<String>> restoreResults(
    WebDavClient client,
    String docDir,
    List<String> names,
  ) async {
    final restored = <String>[];
    for (final name in names) {
      List<int> bytes;
      try {
        bytes = await client.download(name);
      } on WebDavNotFoundException {
        continue;
      }
      final f = File(resolveOutputPath(name, docDir));
      await f.create(recursive: true);
      await f.writeAsBytes(bytes);
      restored.add(name);
    }
    return restored;
  }
}