import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';
import 'package:cfnb_app/features/results/results_table.dart';

void main() {
  const cfg = AppConfig(
    subInputMode: 'node',
    subGenerators: ['CM|sub.cm.com', '洛璃|loli.sub.us.ci'],
  );

  List<ResultRow> sampleRows() => [
        ResultRow('1.1.1.1:443#US CM 洛杉矶 01'),
        ResultRow('2.2.2.2:443#JP 洛璃 东京 02'),
        ResultRow('3.3.3.3:443#US CM 圣何塞 03'),
      ];

  Future<void> pump(WidgetTester tester, List<ResultRow> rows) async {
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async => cfg),
      resultProvider.overrideWith((ref) => ResultNotifier()..setRows(rows, 'addressesapi.txt')),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ResultsTab())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('只显示国家筛选芯片，不再提供来源分类', (tester) async {
    await pump(tester, sampleRows());

    expect(find.text('US 2'), findsOneWidget);
    expect(find.text('JP 1'), findsOneWidget);
    // 来源维度对真实订阅数据不成立（大量行提不出国家码时首段就是原始节点名），
    // 曾炸出上百个芯片，已移除。
    expect(find.text('CM 2'), findsNothing);
    expect(find.text('洛璃 1'), findsNothing);
  });

  testWidgets('点国家芯片后表格只剩该国家的行', (tester) async {
    await pump(tester, sampleRows());

    await tester.tap(find.text('JP 1'));
    await tester.pumpAndSettle();

    // 顶部 N/M 计数反映筛选结果
    expect(find.text('1/3'), findsOneWidget);
    // 只剩一行 → 只应有一张表；注释单元格渲染整段注释
    expect(find.byType(ResultTable), findsOneWidget);
    expect(find.text('US CM 洛杉矶 01'), findsNothing);
    expect(find.text('JP 洛璃 东京 02'), findsOneWidget);

    // 清除筛选恢复全部行
    await tester.tap(find.text('清除筛选'));
    await tester.pumpAndSettle();
    expect(find.text('US CM 洛杉矶 01'), findsOneWidget);
  });

  testWidgets('按国家分组时每组一张表并带组标题', (tester) async {
    await pump(tester, sampleRows());

    await tester.tap(find.text('按国家分组'));
    await tester.pumpAndSettle();

    expect(find.byType(ResultTable), findsNWidgets(2));
    // 组标题：US 2 个 / JP 1 个
    expect(find.text('美国 · 2 个'), findsOneWidget);
    expect(find.text('日本 · 1 个'), findsOneWidget);
  });
}
