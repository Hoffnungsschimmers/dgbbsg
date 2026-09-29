import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_table.dart';

void main() {
  testWidgets('结果表格：长备注单行省略并给出完整 Tooltip', (tester) async {
    const remark = 'US 麒麟 美国 洛杉矶 01 优化专线 0.5x 到期2026-12-31';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ResultTable(rows: [ResultRow('1.1.1.1:443#$remark')]),
      ),
    ));
    // 布局/动画期间若列宽不足产生 RenderFlex 溢出，pumpAndSettle 会直接失败。
    await tester.pumpAndSettle();

    final tip = find.descendant(
      of: find.byType(ResultTable),
      matching: find.byType(Tooltip),
    );
    expect(tip, findsOneWidget);
    expect(tester.widget<Tooltip>(tip).message, remark);

    final text = tester.widget<Text>(find.descendant(of: tip, matching: find.byType(Text)));
    expect(text.data, remark);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
