import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../storage/result_files.dart';
import '../storage/safe_file.dart';
import 'webdav_client.dart';

/// WebDAV 同步服务：配置与结果文件在云盘与本地之间的备份/恢复。
///
/// - 配置备份排除密钥、订阅链接及订阅器鉴权；恢复保留本机这些字段。
/// - 结果文件按文件名逐个上传/下载（含同名 .json 旁文件）。
class WebDavSync {
  WebDavSync._();

  /// 云盘上的配置文件路径。
  static const configFileName = 'cfnb_config.json';

  /// 可同步的普通配置。来源地址本身可能含凭据，也一并排除。
  static Map<String, dynamic> fullConfigJson(AppConfig cfg) {
    final m = cfg.toJson();
    for (final key in ['SUB_URLS', 'SUB_DISABLED_URLS', 'SUB_GENERATORS',
      'SUB_DISABLED_GENERATORS', 'SUB_NODE_UUID']) {
      m.remove(key);
    }
    m['BACKUP_SECRETS_EXCLUDED'] = true;
    return m;
  }

  /// 参与同步的结果文件集合：订阅输出 + 落地输出 + 当前结果文件，各带 .json 旁文件。
  static List<String> resultFileNames(AppConfig cfg, String? currentFile) {
    final names = <String>{};
    if (cfg.subOutputFile.trim().isNotEmpty) {
      names.add(cfg.subOutputFile.trim().split(RegExp(r'[\\/]')).last);
    }
    if (cfg.landingOutputFile.trim().isNotEmpty) {
      names.add(cfg.landingOutputFile.trim().split(RegExp(r'[\\/]')).last);
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

  static Map<String, String> resultLocalPaths(AppConfig cfg, String? currentFile, String docDir) {
    final paths = <String, String>{};
    for (final value in [cfg.subOutputFile, cfg.landingOutputFile, currentFile ?? '']) {
      if (value.trim().isEmpty) continue;
      final local = File(resolveOutputPath(value.trim(), docDir)).absolute.path;
      final name = value.trim().split(RegExp(r'[\\/]')).last;
      if (paths[name] != null && paths[name] != local) {
        throw StateError('不同路径具有相同文件名 $name，无法安全同步');
      }
      paths[name] = local;
      paths['$name.json'] = '$local.json';
    }
    return paths;
  }

  /// 备份配置：上传 cfnb_config.json。
  static Future<void> backupConfig(WebDavClient client, AppConfig cfg) async {
    final bytes = utf8.encode(jsonEncode(fullConfigJson(cfg)));
    await client.upload(configFileName, bytes);
  }

  /// 从云盘拉取配置，返回解析后的 [AppConfig]。
  static Future<AppConfig> restoreConfig(WebDavClient client, {AppConfig? current}) async {
    final bytes = await client.download(configFileName);
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final merged = <String, dynamic>{...?current?.toJson(), ...map};
    // Legacy backups may contain secrets. Missing keys preserve this device's
    // values; excluded backups never overwrite them with blank defaults.
    for (final entry in {
      'GITHUB_TOKEN': current?.githubToken ?? '',
      'WEBHOOK_URL': current?.webhookUrl ?? '',
      'WEBDAV_PASSWORD': current?.webdavPassword ?? '',
    }.entries) {
      if (!map.containsKey(entry.key)) merged[entry.key] = entry.value;
    }
    return AppConfig.fromJson(merged);
  }

  /// 备份结果文件：上传本地存在的结果文件，返回成功上传的文件名列表。
  static Future<List<String>> backupResults(
    WebDavClient client,
    String docDir,
    List<String> names,
    {Map<String, String> localPaths = const {}}
  ) async {
    final uploaded = <String>[];
    for (final name in names) {
      if (name != name.split(RegExp(r'[\\/]')).last || name == '..') throw ArgumentError('结果文件名无效');
      final f = File(localPaths[name] ?? resolveOutputPath(name, docDir));
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
    {Map<String, String> localPaths = const {}}
  ) async {
    final restored = <String>[];
    for (final name in names) {
      if (name != name.split(RegExp(r'[\\/]')).last || name == '..') throw ArgumentError('结果文件名无效');
      List<int> bytes;
      try {
        bytes = await client.download(name);
      } on WebDavNotFoundException {
        continue;
      }
      final f = File(localPaths[name] ?? resolveOutputPath(name, docDir));
      if (name.endsWith('.txt') && f.existsSync()) {
        final oldText = await f.readAsString();
        await writeResultBundle(f, oldText, await readResultMeta(f, oldText));
      }
      await safeWriteBytes(f, bytes);
      restored.add(name);
    }
    return restored;
  }
}
