import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/config/config_repository.dart';
import '../core/fetch/node_parser.dart';
import '../core/github/github_push.dart';
import '../core/logging/app_logger.dart';
import '../core/notification/webhook_sender.dart';

/// 配置仓库（单例）。
final configRepositoryProvider = FutureProvider<ConfigRepository>((ref) async {
  return ConfigRepository.init();
});

/// 节点解析器（从 assets 加载国家码映射）。
final nodeParserProvider = FutureProvider<NodeParser>((ref) async {
  return NodeParser.fromAssets('assets/country_codes.json');
});

/// 订阅器独立日志器（与优选执行日志互相隔离）。
final subLoggerProvider = Provider<AppLogger>((ref) {
  final l = AppLogger();
  ref.onDispose(l.dispose);
  return l;
});

/// 当前生效的配置（从仓库读取）。
final configProvider = FutureProvider<AppConfig>((ref) async {
  final repo = await ref.watch(configRepositoryProvider.future);
  final AppConfig c = repo.current;
  return c;
});

/// 同步持有最新配置（ConfigTab 每次变更立即写入，运行时从此读取，
/// 不受 configProvider 的 Future 链和磁盘写入延迟影响）。
final latestConfigProvider = StateProvider<AppConfig?>((ref) => null);

/// 运行时读取配置的首选方式：优先同步缓存，回退到仓库。
Future<AppConfig> readLatestConfig(Ref ref) async {
  final latest = ref.read(latestConfigProvider);
  if (latest != null) return latest;
  final repo = await ref.read(configRepositoryProvider.future);
  return repo.current;
}

/// 全局主题模式（配置页可切换并自动保存到 AppConfig.guiTheme）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

/// 全局编辑模式开关（Ctrl+E 快捷键切换）。
final editModeProvider = StateProvider<bool>((ref) => false);

/// Webhook 通知发送器（单例 Dio，10 秒超时）。
final webhookSenderProvider = Provider<WebhookSender>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  return WebhookSender(dio);
});

/// GitHub 推送构造器（结果页推送按钮使用）。独立 Provider 便于测试注入
/// mock sender，避免真实网络请求。
final githubPushProvider = Provider<GithubPush Function(AppConfig)>(
  (ref) => (cfg) => GithubPush(
        token: cfg.githubToken,
        repo: cfg.githubRepo,
        branch: cfg.githubBranch,
      ),
);
