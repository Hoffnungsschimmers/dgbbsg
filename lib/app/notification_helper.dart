import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

/// 系统级通知辅助类（Windows Toast / macOS Notification Center / Linux notify）。
///
/// 用于任务完成、错误等场景的桌面通知，与 AppToast（应用内浮层）互补。
/// 当窗口最小化到托盘时，系统通知是用户感知任务完成的主要途径。
class NotificationHelper {
  static bool _initialized = false;

  /// 初始化本地通知器（仅需调用一次）。
  static Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    try {
      await localNotifier.setup(
        appName: 'CFNB',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _initialized = true;
    } catch (_) {
      // 初始化失败不影响主流程
    }
  }

  /// 显示系统通知。
  ///
  /// [title] 通知标题（如「延迟优选完成」）。
  /// [body] 通知正文（如「测试 120 / 连通 85 / 保留 50」）。
  /// [silent] 是否静音（默认 false，会播放系统提示音）。
  static Future<void> show({
    required String title,
    required String body,
    bool silent = false,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) return; // 初始化失败时静默跳过
    try {
      final notification = LocalNotification(
        title: title,
        body: body,
        silent: silent,
      );
      await notification.show();
    } catch (_) {
      // 通知失败不影响主流程
    }
  }

  /// 任务完成通知。
  static Future<void> taskComplete({
    required String taskName,
    required String summary,
  }) async {
    await show(title: '✅ $taskName', body: summary);
  }

  /// 任务失败通知。
  static Future<void> taskFailed({
    required String taskName,
    required String error,
  }) async {
    await show(title: '❌ $taskName 失败', body: error);
  }
}
