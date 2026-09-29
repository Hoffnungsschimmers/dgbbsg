import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/features/subscriptions/config_tab.dart';

void main() {
  testWidgets('配置页:GitHub/WebDAV 已存值回填到输入框', (tester) async {
    final cfg = const AppConfig(
      githubToken: 'ghp_secret_token',
      githubRepo: 'Hoffnungsschimmers/mnscn',
      githubBranch: 'main',
      webdavUrl: 'https://dav.jianguoyun.com/dav/cfnb',
      webdavUser: '2540335944@qq.com',
      webdavPassword: 'pass1234',
    );
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async => cfg),
      configRepositoryProvider.overrideWith((ref) async => throw UnimplementedError()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: ConfigTab())),
    ));
    await tester.pumpAndSettle();

    // 滚动到 GitHub / WebDAV 区域
    await tester.scrollUntilVisible(find.text('GitHub 推送'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    // 断言输入框内容 = 配置值
    TextField fieldWithText(String text) {
      final f = find.byWidgetPredicate(
          (w) => w is TextField && w.controller != null && w.controller!.text == text);
      return tester.widget<TextField>(f.first);
    }

    expect(fieldWithText('ghp_secret_token'), isNotNull);
    expect(fieldWithText('Hoffnungsschimmers/mnscn'), isNotNull);
    expect(fieldWithText('main'), isNotNull);

    await tester.scrollUntilVisible(find.text('WebDAV 同步'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(fieldWithText('https://dav.jianguoyun.com/dav/cfnb'), isNotNull);
    expect(fieldWithText('2540335944@qq.com'), isNotNull);
    expect(fieldWithText('pass1234'), isNotNull);
  });

  testWidgets('配置页:配置先于本页解析完成时也要回填', (tester) async {
    // 真实 App 里主窗口/其它页面会先读 configProvider；等用户切到配置页时
    // 配置早已就绪，此时 listenManual 不会补发当前值 → 输入框全空。
    // 取值刻意区别于默认值，否则回填失败也看不出来。
    const cfg = AppConfig(
      githubRepo: 'Hoffnungsschimmers/saved-repo',
      githubBranch: 'develop',
      webdavUrl: 'https://dav.example.com/dav/saved',
      webdavUser: 'saved@example.com',
    );
    final container = ProviderContainer(overrides: [
      configProvider.overrideWith((ref) async => cfg),
      configRepositoryProvider.overrideWith((ref) async => throw UnimplementedError()),
    ]);
    addTearDown(container.dispose);

    // 挂载前就让配置解析完成。
    await container.read(configProvider.future);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ConfigTab())),
    ));
    await tester.pumpAndSettle();

    bool hasFieldWithText(String text) => find.byWidgetPredicate(
        (w) => w is TextField && w.controller != null && w.controller!.text == text).evaluate().isNotEmpty;

    expect(hasFieldWithText('Hoffnungsschimmers/saved-repo'), isTrue,
        reason: 'GitHub 仓库输入框未回填已保存的配置');
    expect(hasFieldWithText('develop'), isTrue, reason: 'GitHub 分支输入框未回填');
    expect(hasFieldWithText('https://dav.example.com/dav/saved'), isTrue,
        reason: 'WebDAV 地址输入框未回填');
    expect(hasFieldWithText('saved@example.com'), isTrue, reason: 'WebDAV 用户名未回填');
  });
}