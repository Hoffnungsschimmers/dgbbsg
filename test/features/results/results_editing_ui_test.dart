import 'dart:io';

import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/temp_dir.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// 结果页编辑体系的 widget 级覆盖：原始内容视图、编辑节点弹窗、撤销/重做按钮。
/// 这三块此前只有 notifier 级用例（`result_editing_test.dart`），把它们从
/// `results_tab.dart` 拆出时，界面接线需要有人兜着。
///
/// 两个坑：① 编辑动作会写真实文件，fake-async 区里 IO 的 Future 永不完成，
/// 所以点击一律包在 `runAsync` 里；② toast 是挂在 Overlay 上的 3 秒 Timer，
/// 不先把假时钟推过去就会挡住工具栏，导致下一次点击落空。
void main() {
  Directory? dir;

  tearDown(() async {
    final d = dir;
    dir = null;
    if (d != null) await removeTempDir(d);
  });

  Future<ProviderContainer> pumpTab(WidgetTester tester) async {
    // 工具栏按钮多，默认 800×600 会把视图切换与撤销/重做挤到可点击区域之外
    tester.view.physicalSize = const Size(2200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final repo = (await tester
        .runAsync(() => ConfigRepository.init(secure: InMemorySecureKv())))!;
    dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('cfnb_ui_edit'),
    );
    PathProviderPlatform.instance = _FakePathProvider(dir!.path);
    File('${dir!.path}/addressesapi.txt').writeAsStringSync(
      '1.2.3.4:443#US mia\n',
    );

    late ProviderContainer container;
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWith((ref) => repo),
          configProvider.overrideWith(
            (ref) => const AppConfig(subOutputFile: 'addressesapi.txt'),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ResultsTab()),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(tester.element(find.byType(ResultsTab)));
    expect(container.read(resultProvider).rows, hasLength(1));
    return container;
  }

  /// 点击后让真实 IO 跑完，再推进假时钟把可能弹出的 toast 过掉
  Future<void> tapAsync(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('原始内容视图渲染整份文本，非法行整批拒绝且不切视图', (tester) async {
    final container = await pumpTab(tester);

    await tapAsync(tester, find.text('原始'));
    expect(
      find.text('编辑原始内容（修改后切回解析视图自动保存）'),
      findsOneWidget,
    );

    // 原始内容输入框是唯一的 expands 多行框，用它区别于搜索框与添加框
    final rawField = find.byWidgetPredicate(
      (w) => w is TextField && w.expands == true,
    );
    await tester.enterText(
      rawField,
      '1.2.3.4:443#US mia\n5.6.7.8:443#JP nn\nnot-an-address\n',
    );
    await tester.pump();
    await tapAsync(tester, find.text('解析'));

    // 整批拒绝：行数不变，仍停在原始内容视图，并提示具体行号
    expect(container.read(resultProvider).rows, hasLength(1));
    expect(find.text('第 3 行不是有效的地址:端口'), findsOneWidget);
    expect(
      find.text('编辑原始内容（修改后切回解析视图自动保存）'),
      findsOneWidget,
    );

    await tester.enterText(
      rawField,
      '1.2.3.4:443#US mia\n5.6.7.8:443#JP nn\n',
    );
    await tester.pump();
    // 先让上一条 toast 的 3 秒 Timer 走完，否则它会挡住工具栏
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tapAsync(tester, find.text('解析'));

    expect(container.read(resultProvider).rows, hasLength(2));
    expect(
      find.text('编辑原始内容（修改后切回解析视图自动保存）'),
      findsNothing,
    );
    expect(
      File('${dir!.path}/addressesapi.txt').readAsLinesSync(),
      hasLength(2),
    );
  });

  testWidgets('编辑节点弹窗改地址后写回该行', (tester) async {
    final container = await pumpTab(tester);

    await tapAsync(tester, find.text('编辑'));
    expect(find.text('完成'), findsOneWidget);
    // 编辑模式下点击行内任意单元格都走行的 onTap → 打开弹窗（非编辑模式是复制 ip:port）
    await tapAsync(tester, find.text('US mia'));
    expect(find.text('编辑节点'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, '9.9.9.9:443');
    await tapAsync(tester, find.widgetWithText(FilledButton, '保存'));

    expect(find.text('编辑节点'), findsNothing);
    final rows = container.read(resultProvider).rows;
    expect(rows.single.ipPort, '9.9.9.9:443');
    // 来源与国家码沿用原行，改过地址的行不再带实测证据
    expect(rows.single.annotation, contains('mia'));
    expect(rows.single.country, isNotEmpty);
    expect(rows.single.evidence, isEmpty);
    expect(
      File('${dir!.path}/addressesapi.txt').readAsLinesSync().single,
      '9.9.9.9:443#US mia',
    );
  });

  testWidgets('撤销与重做按钮走通 UI 接线并即时落盘', (tester) async {
    final container = await pumpTab(tester);
    final notifier = container.read(resultProvider.notifier);

    notifier.addRow('5.6.7.8:443#JP nn');
    await tester.pumpAndSettle();
    expect(container.read(resultProvider).rows, hasLength(2));

    await tapAsync(tester, find.byTooltip('撤销'));
    expect(container.read(resultProvider).rows, hasLength(1));

    await tapAsync(tester, find.byTooltip('重做'));
    final st = container.read(resultProvider);
    expect(st.rows, hasLength(2));
    expect(st.saving, isFalse);
    expect(st.dirty, isFalse);
    expect(
      File('${dir!.path}/addressesapi.txt').readAsLinesSync(),
      hasLength(2),
    );
  });
}
