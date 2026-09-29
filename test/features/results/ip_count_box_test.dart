import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';

void main() {
  testWidgets('结果页标题行右侧显示 IP 数量框', (tester) async {
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async => const AppConfig(subOutputFile: 'addressesapi.txt')),
      resultProvider.overrideWith((ref) => ResultNotifier()
        ..setRows([
          ResultRow('1.1.1.1:443#US', '30.00 ms'),
          ResultRow('2.2.2.2:443#JP', '50.00 ms'),
        ], 'addressesapi.txt')),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: ResultsTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('IP'), findsOneWidget);
  });
}
