import 'package:cfnb_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// UI 冒烟测试：在真实 Windows 窗口中渲染四页并验证导航与关键组件。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI 冒烟：工作台/优选配置/结果/设置 四页渲染与导航', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // ── 工作台（默认首页）──
    expect(find.text('工作台'), findsWidgets); // 侧边栏 + 页标题
    expect(find.text('顺序执行全部'), findsOneWidget);
    expect(find.text('运行日志'), findsOneWidget);
    expect(find.text('最新优选结果'), findsOneWidget);
    expect(find.text('订阅IP'), findsWidgets); // 行动卡

    // ── 优选配置 ──
    await tester.tap(find.text('优选配置'));
    await tester.pumpAndSettle();
    expect(find.text('整理', skipOffstage: false), findsNothing);
    expect(find.text('数据源'), findsWidgets);
    expect(find.text('订阅转换'), findsWidgets);
    expect(find.text('延迟优选'), findsWidgets);
    expect(find.text('带宽测速'), findsWidgets);
    // 默认分组：数据源 → 候选订阅器
    expect(find.text('候选订阅器'), findsOneWidget);
    expect(find.text('输入模式'), findsWidgets); // 分组卡标题 + 字段标签

    // 切到「延迟优选」分组
    await tester.tap(find.text('延迟优选').first);
    await tester.pumpAndSettle();
    expect(find.text('延迟低于(ms)'), findsOneWidget);
    expect(find.text('连接超时(秒)'), findsOneWidget);
    expect(find.text('质量延迟权重'), findsOneWidget);

    // 切到「带宽测速」分组
    await tester.tap(find.text('带宽测速').first);
    await tester.pumpAndSettle();
    expect(find.text('仅测延迟≤(ms)'), findsOneWidget);
    expect(find.text('带宽参考值(Mbps)'), findsOneWidget);

    // ── 结果页 ──
    await tester.tap(find.text('结果'));
    await tester.pumpAndSettle();
    expect(find.text('优选结果'), findsOneWidget);
    expect(find.text('复制 CSV'), findsNothing); // 无数据时不出现

    // ── 设置页 ──
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub 推送（独立 cf-ip 仓库）'), findsOneWidget);
    expect(find.text('外观'), findsWidgets);
    expect(find.textContaining('附加数据源'), findsWidgets);
    expect(find.text('关于'), findsOneWidget);

    // 回到工作台
    await tester.tap(find.text('工作台').first);
    await tester.pumpAndSettle();
    expect(find.text('顺序执行全部'), findsOneWidget);
  });
}