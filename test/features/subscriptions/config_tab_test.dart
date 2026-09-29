import 'dart:io';

import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/features/subscriptions/config_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

Finder _fieldByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  group('ConfigTab', () {
    late ConfigRepository repo;
    late Directory dir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = await ConfigRepository.init(secure: InMemorySecureKv());
      dir = await Directory.systemTemp.createTemp('cfnb_config_test');
      PathProviderPlatform.instance = _FakePathProvider(dir.path);
    });

    tearDown(() async {
      // 让 tearDown 阶段残留的异步任务（防抖保存/重载）完成，避免进程挂起
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> pumpTab(WidgetTester tester, {AppConfig? cfg}) async {
      await repo.save(cfg ?? const AppConfig(subDefaultCountry: 'US', subInputMode: 'url'));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWith((ref) => repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: ConfigTab()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('输入字符时不应触发全选（同步不覆盖聚焦字段）', (tester) async {
      await pumpTab(tester);

      final field = _fieldByHint('留空=不设');
      expect(field, findsOneWidget);
      final ctl = tester.widget<TextField>(field).controller!;
      expect(ctl.text, 'US');

      await tester.enterText(field, 'j');
      // 触发配置重载（模拟防抖保存后的 invalidate 回写路径）
      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      container.invalidate(configProvider);
      await tester.pumpAndSettle();

      // 正在编辑时：文本保持用户输入，选择范围合法（不为 -1 全选）
      expect(ctl.text, 'j');
      expect(ctl.selection.isValid, isTrue);
      expect(ctl.selection.baseOffset, 1);
    });

    testWidgets('失焦后同步回写规范化值且选择合法', (tester) async {
      await pumpTab(tester);

      final field = _fieldByHint('留空=不设');
      final ctl = tester.widget<TextField>(field).controller!;

      await tester.enterText(field, 'jp');
      await tester.pump();
      expect(ctl.text, 'jp');

      // 失焦后配置外部变更：未聚焦的字段应回写规范化值（大写）且选择合法
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      await repo.save(const AppConfig(subDefaultCountry: 'JP', subInputMode: 'url'));
      container.invalidate(configProvider);
      await container.read(configProvider.future);
      await tester.pump();

      expect(ctl.text, 'JP');
      expect(ctl.selection.isValid, isTrue);

      // 卸载 widget 触发 dispose，取消防抖定时器，避免测试残留异步
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('输入模式用 ChoiceChip 切换', (tester) async {
      await pumpTab(tester);

      expect(find.byType(ChoiceChip), findsWidgets);
      await tester.tap(find.widgetWithText(ChoiceChip, '订阅器'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      expect(container.read(configProvider).valueOrNull?.subInputMode, 'node');

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('订阅链接卡片点击弹出编辑对话框（备注+链接双框）', (tester) async {
      await pumpTab(tester, cfg: const AppConfig(
        subInputMode: 'url',
        subUrls: ['备注A|https://example.com/sub1'],
      ));

      // 卡片静态显示备注与链接
      expect(find.text('备注A'), findsOneWidget);
      expect(find.text('https://example.com/sub1'), findsOneWidget);

      // 点击卡片 → 弹窗出现两个输入框
      await tester.tap(find.text('备注A'));
      await tester.pumpAndSettle();
      expect(find.text('编辑订阅链接'), findsOneWidget);
      expect(find.byKey(const Key('editor_note')), findsOneWidget);
      expect(find.byKey(const Key('editor_value')), findsOneWidget);

      // 修改链接并保存
      await tester.enterText(
          find.byKey(const Key('editor_value')), 'https://example.com/sub2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('https://example.com/sub2'), findsOneWidget);
      expect(find.text('备注A'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('添加订阅链接走弹窗（备注+链接）', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(find.text('添加订阅链接'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('editor_note')), '备注X');
      await tester.enterText(
          find.byKey(const Key('editor_value')), 'https://example.com/x');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('备注X'), findsOneWidget);
      expect(find.text('https://example.com/x'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('订阅器卡片编辑含密钥字段', (tester) async {
      await pumpTab(tester, cfg: const AppConfig(
        subInputMode: 'node',
        subGenerators: ['名称A|example.com'],
      ));

      expect(find.text('名称A'), findsOneWidget);
      await tester.tap(find.text('名称A'));
      await tester.pumpAndSettle();
      expect(find.text('编辑订阅器'), findsOneWidget);
      expect(find.byKey(const Key('editor_secret')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('editor_secret')), 'abc-secret');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      expect(container.read(configProvider).valueOrNull?.subGenerators,
          ['名称A|example.com|abc-secret']);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('WebDAV 区块可展开并编辑保存服务器地址', (tester) async {
      await pumpTab(tester);

      // 区块默认展开（initiallyExpanded: true）→ 滚动到可见后直接断言字段
      await tester.scrollUntilVisible(find.text('WebDAV 同步'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('服务器地址'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('服务器地址'), findsOneWidget);
      expect(find.text('账号'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('自动同步'), findsOneWidget);

      // 输入服务器地址并保存到配置
      final field = _fieldByHint('https://dav.jianguoyun.com/dav');
      await tester.enterText(field, 'https://dav.jianguoyun.com/dav');
      await tester.pumpAndSettle();

      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      expect(
          container.read(configProvider).valueOrNull?.webdavUrl,
          'https://dav.jianguoyun.com/dav');

      // 密码框为密文
      final passField = find.byWidgetPredicate(
          (w) => w is TextField && w.obscureText && w.controller != null);
      expect(passField, findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('WebDAV 自动同步开关开启后显示间隔滑块', (tester) async {
      await pumpTab(tester);

      // 区块默认展开 → 直接滚到「自动同步」开关
      await tester.scrollUntilVisible(find.text('自动同步'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('自动同步间隔（分钟）'), findsNothing);

      await tester.tap(find.text('自动同步'));
      await tester.pumpAndSettle();
      expect(find.text('自动同步间隔（分钟）'), findsOneWidget);

      final container =
          ProviderScope.containerOf(tester.element(find.byType(ConfigTab)));
      expect(container.read(configProvider).valueOrNull?.webdavAutoSync, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
