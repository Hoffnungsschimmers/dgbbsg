import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';
import 'package:cfnb_app/app/providers.dart';

/// 窄屏（手机 360dp 宽度）下三个页面不溢出渲染。
void main() {
  Future<void> pumpNarrow(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('窄屏:结果页标题行不溢出(时间/IP框可见)', (tester) async {
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async => const AppConfig(subOutputFile: 'addressesapi.txt')),
      resultProvider.overrideWith((ref) => ResultNotifier()
        ..setRows([
          ResultRow('1.1.1.1:443#US', '30.00 ms'),
          ResultRow('2.2.2.2:443#JP', '50.00 ms'),
        ], 'addressesapi.txt')),
    ]);
    addTearDown(container.dispose);
    await pumpNarrow(tester, UncontrolledProviderScope(container: container, child: const ResultsTab()));

    final errors = tester.takeException();
    expect(errors, isNull, reason: '结果页窄屏渲染不应有溢出异常');
    expect(find.text('订阅结果'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // IP 框数字
    expect(find.text('IP'), findsOneWidget);
  });
}