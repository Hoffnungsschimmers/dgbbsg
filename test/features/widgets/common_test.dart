import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/logging/app_logger.dart';
import 'package:cfnb_app/features/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用包装器：提供 MaterialApp + Theme 上下文。
Widget _wrap(Widget child, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: Scaffold(body: child),
  );
}

void main() {
  group('card()', () {
    testWidgets('渲染子组件', (tester) async {
      await tester.pumpWidget(_wrap(const _CardTest()));
      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('pill()', () {
    testWidgets('显示文本', (tester) async {
      await tester.pumpWidget(_wrap(const _PillTest()));
      expect(find.text('测试药丸'), findsOneWidget);
    });
  });

  group('pillWithIcon()', () {
    testWidgets('显示图标和文本', (tester) async {
      await tester.pumpWidget(_wrap(const _PillWithIconTest()));
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.text('3 分钟前'), findsOneWidget);
    });
  });

  group('AppButton', () {
    testWidgets('主按钮渲染', (tester) async {
      await tester.pumpWidget(_wrap(const AppButton('点击', onPressed: null)));
      expect(find.text('点击'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('次按钮渲染', (tester) async {
      await tester.pumpWidget(_wrap(const AppButton('取消', primary: false, onPressed: null)));
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('带图标', (tester) async {
      await tester.pumpWidget(_wrap(const AppButton('运行', icon: Icons.play_arrow, onPressed: null)));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });
  });

  group('CountUpText', () {
    testWidgets('显示数值', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(42)));
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('带小数位', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(3.14, decimals: 2)));
      await tester.pumpAndSettle();
      expect(find.text('3.14'), findsOneWidget);
    });

    testWidgets('带后缀', (tester) async {
      await tester.pumpWidget(_wrap(const CountUpText(100, suffix: ' ms')));
      await tester.pumpAndSettle();
      expect(find.text('100 ms'), findsOneWidget);
    });
  });

  group('SectionCollapsible', () {
    testWidgets('默认展开显示子组件', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionCollapsible(title: '折叠区', child: Text('内容')),
      ));
      expect(find.text('折叠区'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('点击折叠后隐藏子组件', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionCollapsible(title: '折叠区', child: Text('内容')),
      ));
      await tester.tap(find.text('折叠区'));
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsNothing);
    });

    testWidgets('初始折叠时不显示子组件', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionCollapsible(title: '折叠区', initiallyExpanded: false, child: Text('内容')),
      ));
      expect(find.text('内容'), findsNothing);
    });
  });

  group('RawTextView', () {
    testWidgets('显示文本内容', (tester) async {
      await tester.pumpWidget(_wrap(const RawTextView('1.2.3.4:443#US')));
      expect(find.text('1.2.3.4:443#US'), findsOneWidget);
    });

    testWidgets('复制按钮存在', (tester) async {
      await tester.pumpWidget(_wrap(const RawTextView('test content')));
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });
  });

  group('LogView', () {
    testWidgets('空日志显示提示', (tester) async {
      final logger = AppLogger();
      await tester.pumpWidget(_wrap(LogView(logger: logger)));
      await tester.pumpAndSettle();
      expect(find.text('暂无日志'), findsOneWidget);
      logger.dispose();
    });

    testWidgets('自定义空提示', (tester) async {
      final logger = AppLogger();
      await tester.pumpWidget(_wrap(LogView(logger: logger, emptyHint: '等待运行…')));
      await tester.pumpAndSettle();
      expect(find.text('等待运行…'), findsOneWidget);
      logger.dispose();
    });
  });

  group('labeledSliderCountUp()', () {
    testWidgets('显示标签和滑块', (tester) async {
      await tester.pumpWidget(_wrap(const _LabeledSliderTest()));
      expect(find.text('并发数'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
  });

  group('AppToast', () {
    testWidgets('显示消息', (tester) async {
      await tester.pumpWidget(_wrap(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppToast.show(ctx, '操作成功'),
            child: const Text('触发'),
          ),
        ),
      ));
      await tester.tap(find.text('触发'));
      await tester.pump();
      expect(find.text('操作成功'), findsOneWidget);
    });
  });
}

// ── 测试辅助 Widget：使用 Builder 获取 BuildContext ──

class _CardTest extends StatelessWidget {
  const _CardTest();
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => card(ctx, child: const Text('hello')),
    );
  }
}

class _PillTest extends StatelessWidget {
  const _PillTest();
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => pill(ctx, '测试药丸', Colors.blue),
    );
  }
}

class _PillWithIconTest extends StatelessWidget {
  const _PillWithIconTest();
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => pillWithIcon(ctx, icon: Icons.schedule, text: '3 分钟前', bg: Colors.grey),
    );
  }
}

class _LabeledSliderTest extends StatelessWidget {
  const _LabeledSliderTest();
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => labeledSliderCountUp(ctx, '并发数', 50, 1, 500, (_) {}),
    );
  }
}
