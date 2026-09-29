import 'package:cfnb_app/app/app.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/features/subscriptions/config_tab.dart';
import 'package:cfnb_app/features/subscriptions/subscriptions_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试用安全 notifier：避免 SubscriptionsNotifier 的 onDispose 双重释放断言
/// （StateNotifier 非幂等，debug 模式第二次 dispose 抛错）。
class _SafeSubNotifier extends SubscriptionsNotifier {
  _SafeSubNotifier(super.ref);

  @override
  // ignore: must_call_super  // 诊断落在方法声明行，注释必须紧贴它
  void dispose() {
    stopAutoUpdate();
  }
}

void main() {
  testWidgets('首帧首页（配置页）透明度为 1，无需切页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        configRepositoryProvider.overrideWith((ref) => repo),
        configProvider.overrideWith((ref) async => const AppConfig()),
        subProvider.overrideWith((ref) => _SafeSubNotifier(ref)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AppShell(),
      ),
    ));
    await tester.pump();

    // _TabStack 的 FadeTransition 是 ConfigTab 最近的一个 FadeTransition 祖先
    final fade = tester.widget<FadeTransition>(find
        .ancestor(of: find.byType(ConfigTab), matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1.0);
    expect(find.byType(ConfigTab), findsOneWidget);

    // 清理 flutter_animate 的一次性动画 timer 与未完成异步，避免测试残留
    await tester.pumpAndSettle();
  });
}