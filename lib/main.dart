import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'app/motion.dart';
import 'app/providers.dart';
import 'app/system_tray.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';
import 'core/webdav/webdav_client.dart';
import 'core/webdav/webdav_sync.dart';
import 'features/onboarding/onboarding_wizard.dart';
import 'features/results/result_state.dart';
import 'features/subscriptions/subscriptions_state.dart';
import 'features/widgets/common.dart';
import 'package:path_provider/path_provider.dart';

/// Global instance so the app shell can access it.
final SystemTrayManager systemTrayManager = SystemTrayManager();

/// 桌面平台（window_manager / system_tray 仅支持桌面端）。
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window_manager for desktop platforms.
  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      minimumSize: Size(800, 600),
      title: 'CFNB - CF优选工具',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WindowListener {
  DateTime? _lastBackPress;
  Timer? _wdAutoSyncTimer;
  int? _wdAutoSyncMinutes;

  @override
  void initState() {
    super.initState();
    // 初始状态栏样式
    _applySystemUI(ThemeMode.light);

    if (isDesktopPlatform) {
      // Prevent the window from actually closing; hide to tray instead.
      windowManager.setPreventClose(true);
      windowManager.addListener(this);

      // Initialize the system tray after the first frame so context is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initSystemTray());
    }
  }

  @override
  void dispose() {
    _wdAutoSyncTimer?.cancel();
    if (isDesktopPlatform) {
      windowManager.removeListener(this);
      systemTrayManager.dispose();
    }
    super.dispose();
  }

  /// Called by window_manager when the user clicks the close button.
  @override
  void onWindowClose() {
    systemTrayManager.hideToTray();
  }

  /// 根据配置启停 WebDAV 自动同步定时器（间隔变化时重建）。
  void _syncWebDavAutoSync(AppConfig cfg) {
    if (!cfg.webdavAutoSync) {
      _wdAutoSyncTimer?.cancel();
      _wdAutoSyncTimer = null;
      _wdAutoSyncMinutes = null;
      return;
    }
    final minutes = cfg.webdavAutoSyncIntervalMin.clamp(5, 480);
    if (_wdAutoSyncTimer != null && _wdAutoSyncMinutes == minutes) return;
    _wdAutoSyncTimer?.cancel();
    _wdAutoSyncMinutes = minutes;
    _wdAutoSyncTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      _runWebDavAutoSync();
    });
  }

  /// 自动同步：推送配置 + 结果文件（失败静默，下次到点重试）。
  Future<void> _runWebDavAutoSync() async {
    try {
      var cfg = ref.read(latestConfigProvider);
      cfg ??= (await ref.read(configRepositoryProvider.future)).current;
      if (!cfg.webdavAutoSync || cfg.webdavUrl.trim().isEmpty) return;
      final client = WebDavClient(
        baseUrl: cfg.webdavUrl.trim(),
        user: cfg.webdavUser.trim(),
        password: cfg.webdavPassword,
      );
      await WebDavSync.backupConfig(client, cfg);
      final docDir = (await getApplicationDocumentsDirectory()).path;
      final names = WebDavSync.resultFileNames(cfg, ref.read(resultProvider).currentFile);
      await WebDavSync.backupResults(client, docDir, names);
    } catch (_) {
      // 自动同步失败静默（不打扰用户，下次到点重试）。
    }
  }

  /// 首次启动引导：hasCompletedOnboarding 为 false 时弹全屏引导页。
  /// 引导完成（或跳过）后落盘标记，仅弹一次。
  Future<void> _maybeShowOnboarding(AppConfig cfg) async {
    if (cfg.hasCompletedOnboarding) return;
    // 等首帧渲染完成再弹，避免 Navigator 尚未就绪。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final repo = await ref.read(configRepositoryProvider.future);
        // 二次确认：等待期间用户可能已在引导页完成配置。
        if (repo.current.hasCompletedOnboarding) return;
        if (!mounted || !context.mounted) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => OnboardingWizard(repo: repo),
          ),
        );
      } catch (_) {
        // 引导展示失败不影响主流程
      }
    });
  }

  Future<void> _initSystemTray() async {
    await systemTrayManager.init(
      onShow: () => systemTrayManager.showWindow(),
      onRunSub: () {
        systemTrayManager.showWindow();
        ref.read(subProvider.notifier).runSubscription();
      },
      onQuit: () async {
        systemTrayManager.dispose();
        await windowManager.destroy();
      },
    );
  }

  /// 根据主题模式更新系统状态栏/导航栏样式（沉浸式 + 透明）
  void _applySystemUI(ThemeMode mode) {
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));
  }

  /// 预测式返回手势 / Android 物理返回键处理
  /// - 非首页 Tab → 返回首页
  /// - 首页 → 2 秒内连按两次才退出
  Future<bool> _handleBack() async {
    final tab = ref.read(tabProvider);
    if (tab != 0) {
      ref.read(tabProvider.notifier).state = 0;
      return false; // 阻止退出
    }
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      return true; // 允许退出
    }
    _lastBackPress = now;
    if (mounted) AppToast.show(context, '再按一次退出');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);

    // 监听主题变化 → 更新状态栏
    ref.listen(themeModeProvider, (_, next) => _applySystemUI(next));

    // 首次加载：从持久化配置读取主题偏好；未完成引导时弹出引导页。
    ref.listen(configProvider, (_, next) {
      next.whenData((cfg) {
        final ThemeMode initial = switch (cfg.guiTheme) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        };
        if (ref.read(themeModeProvider) != initial) {
          ref.read(themeModeProvider.notifier).state = initial;
        }
        _syncWebDavAutoSync(cfg);
        _maybeShowOnboarding(cfg);
      });
    });

    return MaterialApp(
      title: 'CF优选工具',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      themeAnimationDuration: Motion.durTheme,
      themeAnimationCurve: Motion.curveEmphasized,
      // 限制系统字号缩放（防止过大字号破坏布局）
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.85,
        maxScaleFactor: 1.3,
        child: child!,
      ),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final shouldPop = await _handleBack();
          if (!mounted) return;
          if (shouldPop) {
            SystemNavigator.pop();
          }
        },
        child: const AppShell(),
      ),
    );
  }
}
