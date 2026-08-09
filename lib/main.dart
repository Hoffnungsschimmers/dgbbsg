import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/motion.dart';
import 'app/platform.dart';
import 'app/providers.dart';
import 'app/theme.dart';
import 'features/widgets/common.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    // 初始状态栏样式
    _applySystemUI(ThemeMode.light);
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

    // 首次加载：从持久化配置读取主题偏好
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
