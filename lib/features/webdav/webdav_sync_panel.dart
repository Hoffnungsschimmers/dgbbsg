import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/webdav/webdav_client.dart';
import '../../core/webdav/webdav_sync.dart';
import '../results/result_state.dart';

/// 顶栏 WebDAV 同步入口：弹出「同步配置 / 同步结果」两个选项，
/// 各自可推送备份或拉取恢复。
///
/// [clientBuilder] 仅测试注入用（默认按配置创建真实客户端）。
Future<void> showWebDavSyncSheet(
  BuildContext context,
  WidgetRef ref, {
  WebDavClient Function(AppConfig)? clientBuilder,
}) async {
  final cfg = ref.read(latestConfigProvider);
  if (cfg == null || cfg.webdavUrl.trim().isEmpty || cfg.webdavUser.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('请先在「配置」页填写 WebDAV 服务器地址与账号')),
    );
    return;
  }

  final buildClient = clientBuilder ?? _defaultClient;

  final t = AppThemeExt.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: t.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_sync_outlined,
                  size: 18, color: AppTheme.edgeOrange),
              const SizedBox(width: 8),
              Text(
                'WebDAV 同步',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.textDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.settings_outlined,
                color: AppTheme.edgeOrange),
            title: Text('同步配置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
            subtitle: Text('备份 / 恢复 cfnb_config.json',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            onTap: () => Navigator.pop(ctx, 'config'),
          ),
          ListTile(
            leading: Icon(Icons.description_outlined,
                color: AppTheme.edgeOrange),
            title: Text('同步结果',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
            subtitle: Text('备份 / 恢复结果 TXT 与 JSON 文件',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            onTap: () => Navigator.pop(ctx, 'results'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(choice == 'config' ? '同步配置' : '同步结果'),
      content: const Text('选择操作：'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, 'push'),
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: const Text('推送备份'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, 'pull'),
          icon: const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('拉取恢复'),
        ),
      ],
    ),
  );
  if (action == null || !context.mounted) return;

  await _runSync(context, ref, cfg, buildClient, choice == 'config', action == 'push');
}

WebDavClient _defaultClient(AppConfig cfg) => WebDavClient(
      baseUrl: cfg.webdavUrl.trim(),
      user: cfg.webdavUser.trim(),
      password: cfg.webdavPassword,
    );

Future<void> _runSync(
  BuildContext context,
  WidgetRef ref,
  AppConfig cfg,
  WebDavClient Function(AppConfig) buildClient,
  bool isConfig,
  bool isPush,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(width: 16),
          Text('同步中…'),
        ],
      ),
    ),
  );

  String message;
  try {
    final client = buildClient(cfg);
    if (isConfig) {
      if (isPush) {
        await WebDavSync.backupConfig(client, cfg);
        message = '配置已备份到 WebDAV';
      } else {
        final restored = await WebDavSync.restoreConfig(client);
        final repo = await ref.read(configRepositoryProvider.future);
        await repo.save(restored);
        ref.invalidate(configProvider);
        message = '配置已从 WebDAV 恢复';
      }
    } else {
      final docDir = (await getApplicationDocumentsDirectory()).path;
      final currentFile = ref.read(resultProvider).currentFile;
      final names = WebDavSync.resultFileNames(cfg, currentFile);
      if (isPush) {
        final uploaded = await WebDavSync.backupResults(client, docDir, names);
        message = '已备份 ${uploaded.length} 个结果文件';
      } else {
        final restored = await WebDavSync.restoreResults(client, docDir, names);
        if (restored.isNotEmpty) {
          ref.read(resultProvider.notifier).refreshFile(cfg.subOutputFile);
        }
        message = '已恢复 ${restored.length} 个结果文件';
      }
    }
  } on WebDavNotFoundException {
    message = '云盘上没有备份文件（404），请先推送备份';
  } on DioException catch (e) {
    final code = e.response?.statusCode;
    message = switch (code) {
      404 => '目标路径不存在（404）：请检查服务器地址，或先在云盘创建对应目录',
      null => '同步失败：网络错误（${e.type.name}）',
      _ => '同步失败：服务器返回 HTTP $code',
    };
  } catch (e) {
    message = '同步失败：$e';
  }

  if (navigator.mounted) navigator.pop();
  messenger.showSnackBar(SnackBar(content: Text(message)));
}