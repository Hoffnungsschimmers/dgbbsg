import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/net/landing_history.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';
import 'package:cfnb_app/features/subscriptions/subscriptions_state.dart';

void main() {
  Future<void> pumpTab(WidgetTester tester, List<ResultRow> rows, LandingHistory history) async {
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async =>
          const AppConfig(subInputMode: 'node', subGenerators: ['麒麟|sub.qilin.com'])),
      resultProvider.overrideWith(
          (ref) => ResultNotifier()..setRows(rows, 'addressesapi_top.txt')),
      landingHistoryProvider.overrideWith((ref) async => history),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ResultsTab())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('结果页可打开落地历史面板，展开看到历次落地与当时出口', (tester) async {
    await pumpTab(
      tester,
      [ResultRow('1.1.1.1:443#US 麒麟 洛杉矶 01')],
      {
        '1.1.1.1': [
          const LandingObservation(
              at: '2026-09-29 21:00:00', colo: 'LAX', cc: 'US', egressIp: '203.0.113.9'),
          const LandingObservation(
              at: '2026-09-29 20:00:00', colo: 'HKG', cc: 'HK', egressIp: '203.0.113.7'),
        ],
      },
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('落地历史'), findsOneWidget);
    expect(find.text('当前 US · 记录了 2 次变化'), findsOneWidget);

    await tester.tap(find.text('1.1.1.1'));
    await tester.pumpAndSettle();

    // 两条历史观测都可见，并带着当时的出口身份
    expect(find.textContaining('HKG → HK'), findsOneWidget);
    expect(find.textContaining('LAX → US'), findsOneWidget);
    expect(find.textContaining('出口 203.0.113.7'), findsOneWidget);
  });

  testWidgets('没有落地历史时给出下一步指引而不是报错', (tester) async {
    await pumpTab(tester, [ResultRow('2.2.2.2:443#JP 洛璃 东京 02')], {});

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('还没有落地记录：先在运行页点「测落地」。'), findsOneWidget);
  });

  testWidgets('搜索框按 IP 过滤历史条目', (tester) async {
    await pumpTab(
      tester,
      [ResultRow('1.1.1.1:443#US 麒麟 洛杉矶 01')],
      {
        '1.1.1.1': const [
          LandingObservation(at: '2026-09-29 20:00:00', colo: 'HKG', cc: 'HK'),
        ],
        '8.8.8.8': const [
          LandingObservation(at: '2026-09-29 20:00:00', colo: 'SIN', cc: 'SG'),
        ],
      },
    );

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(find.text('8.8.8.8'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '1.1.1');
    await tester.pumpAndSettle();
    expect(find.text('1.1.1.1'), findsOneWidget);
    expect(find.text('8.8.8.8'), findsNothing);
  });
}
