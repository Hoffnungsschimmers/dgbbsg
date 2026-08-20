import 'dart:io';

import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/results/results_tab.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

void main() {
  group('parseLatency()', () {
    test('解析 "50.00 ms" 格式', () {
      expect(parseLatency('50.00 ms'), 50.0);
    });

    test('解析 "50.00ms" 格式（无空格）', () {
      expect(parseLatency('50.00ms'), 50.0);
    });

    test('解析纯数字', () {
      expect(parseLatency('123.45'), 123.45);
    });

    test('null 返回 null', () {
      expect(parseLatency(null), isNull);
    });

    test('空字符串返回 null', () {
      expect(parseLatency(''), isNull);
    });

    test('非数字返回 null', () {
      expect(parseLatency('abc'), isNull);
    });
  });

  group('ResultRow', () {
    test('ipPort 提取正确', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.ipPort, '1.2.3.4:443');
    });

    test('country 提取正确', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.country, isNotEmpty);
    });

    test('source 提取（空格分隔）', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.source, 'mia');
    });

    test('source 提取（@ 分隔，旧格式）', () {
      final row = ResultRow('1.2.3.4:443#US@cm', '50.00 ms');
      expect(row.source, 'cm');
    });

    test('无来源时 source 为空', () {
      final row = ResultRow('1.2.3.4:443#US', '50.00 ms');
      expect(row.source, isEmpty);
    });
  });

  group('parseResultLines()', () {
    test('解析新格式（空格分隔）', () {
      const text = '1.2.3.4:443#US mia 50.00 ms\n'
          '5.6.7.8:443#JP nrt 120.50ms\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(2));
      expect(rows[0].ipPort, '1.2.3.4:443');
      expect(rows[0].latency, '50.00 ms');
      expect(rows[1].ipPort, '5.6.7.8:443');
      expect(rows[1].latency, '120.50ms');
    });

    test('解析旧格式（@ 分隔）', () {
      const text = '1.2.3.4:443#US@cm 50.00 ms\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
      expect(rows[0].latency, '50.00 ms');
    });

    test('纯节点（无延迟）', () {
      const text = '1.2.3.4:443#US\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
      expect(rows[0].latency, isNull);
    });

    test('跳过空行和注释', () {
      const text = '# 注释\n\n1.2.3.4:443#US\n\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
    });

    test('跳过不含冒号的行', () {
      const text = 'invalid line\n1.2.3.4:443#US\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
    });
  });

  group('ResultNotifier', () {
    late ResultNotifier notifier;

    setUp(() {
      notifier = ResultNotifier();
    });

    test('初始状态为空', () {
      expect(notifier.state.rows, isEmpty);
      expect(notifier.state.currentFile, isNull);
    });

    test('setRows 更新状态', () {
      notifier.setRows([ResultRow('1.2.3.4:443#US')], 'test.txt');
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.sourceLabel, 'test.txt');
    });

    test('addRow 添加节点', () {
      notifier.addRow('1.2.3.4:443#US');
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.rows[0].ipPort, '1.2.3.4:443');
    });

    test('addRow 忽略空行', () {
      notifier.addRow('');
      notifier.addRow('   ');
      expect(notifier.state.rows, isEmpty);
    });

    test('addRow 忽略无冒号行', () {
      notifier.addRow('invalid');
      expect(notifier.state.rows, isEmpty);
    });

    test('removeRow 删除指定索引', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.addRow('2.2.2.2:443#JP');
      notifier.removeRow(0);
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.rows[0].ipPort, '2.2.2.2:443');
    });

    test('removeRow 越界不崩溃', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.removeRow(99);
      notifier.removeRow(-1);
      expect(notifier.state.rows, hasLength(1));
    });

    test('updateRow 更新节点', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.updateRow(0, '2.2.2.2:443#JP');
      expect(notifier.state.rows[0].ipPort, '2.2.2.2:443');
    });

    test('updateRow 保留延迟', () {
      notifier.setRows([ResultRow('1.1.1.1:443#US', '50 ms')]);
      notifier.updateRow(0, '2.2.2.2:443#JP');
      expect(notifier.state.rows[0].latency, '50 ms');
    });

    test('updateRow 越界不崩溃', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.updateRow(99, '2.2.2.2:443#JP');
      expect(notifier.state.rows, hasLength(1));
    });

    test('toText 序列化 node 与延迟', () {
      notifier.setRows([
        ResultRow('1.2.3.4:443#US mia', '50.00 ms'),
        ResultRow('5.6.7.8:443#JP'),
      ]);
      expect(notifier.state.toText(),
          '1.2.3.4:443#US mia 50.00 ms\n5.6.7.8:443#JP\n');
    });

    test('toText 空列表输出空字符串', () {
      expect(notifier.state.toText(), '');
    });
  });

  group('ResultsTab', () {
    testWidgets('启动时自动加载配置指定的结果文件', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = (await tester
          .runAsync(() => ConfigRepository.init(secure: InMemorySecureKv())))!;
      final dir = (await tester
          .runAsync(() => Directory.systemTemp.createTemp('cfnb_test')))!;
      addTearDown(() async {
        for (var attempt = 0; attempt < 5; attempt++) {
          try {
            await dir.delete(recursive: true);
            return;
          } catch (_) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
      });

      PathProviderPlatform.instance = _FakePathProvider(dir.path);
      File('${dir.path}/addressesapi.txt')
          .writeAsStringSync('1.2.3.4:443#US mia 50.00 ms\n');

      await tester.runAsync(() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            configRepositoryProvider.overrideWith((ref) => repo),
            configProvider.overrideWith(
              (ref) async => const AppConfig(subOutputFile: 'addressesapi.txt'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: ResultsTab()),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(ResultsTab));
      final state = ProviderScope.containerOf(ctx).read(resultProvider);
      expect(state.currentFile, 'addressesapi.txt');
      expect(state.rows, hasLength(1));
      expect(state.rows[0].ipPort, '1.2.3.4:443');
      expect(find.textContaining('1.2.3.4', findRichText: true), findsOneWidget);
      expect(find.text('US mia'), findsOneWidget);
    });

    test('refreshFile 回退到默认文件（currentFile 为空时）', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dir = await Directory.systemTemp.createTemp('cfnb_test');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/fallback.txt')
          .writeAsStringSync('9.9.9.9:443#US fallback 10.00 ms\n');

      PathProviderPlatform.instance = _FakePathProvider(dir.path);
      final notifier = container.read(resultProvider.notifier);
      await notifier.refreshFile('fallback.txt');

      expect(notifier.state.currentFile, 'fallback.txt');
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.rows[0].ipPort, '9.9.9.9:443');
    });

    Future<void> pumpResultsTab(
      WidgetTester tester, {
      required ProviderContainer container,
    }) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: ResultsTab()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('地址按钮弹出选择列表，可复制源地址', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubRepo: 'Hoffnungsschimmers/mnscn',
              githubBranch: 'main',
            )),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '地址'));
      await tester.pumpAndSettle();

      // 对话框列出源地址 + 镜像
      expect(find.text('选择要复制的地址'), findsOneWidget);
      expect(find.text('源（GitHub Raw）'), findsOneWidget);
      expect(find.text('jsDelivr CDN'), findsOneWidget);

      await tester.tap(find.text('源（GitHub Raw）'));
      await tester.pumpAndSettle();

      final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      expect((setData.arguments as Map)['text'],
          'https://raw.githubusercontent.com/Hoffnungsschimmers/mnscn/refs/heads/main/addressesapi.txt');
    });

    testWidgets('地址选择可复制 jsDelivr 镜像地址', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubRepo: 'Hoffnungsschimmers/mnscn',
              githubBranch: 'main',
            )),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '地址'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('jsDelivr CDN'));
      await tester.pumpAndSettle();

      final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
      expect((setData.arguments as Map)['text'],
          'https://cdn.jsdelivr.net/gh/Hoffnungsschimmers/mnscn@main/addressesapi.txt');
    });

    testWidgets('推送按钮成功后提示并完成 API 调用', (tester) async {
      final apiCalls = <String>[];
      Future<Response<dynamic>> fakeSender(RequestOptions o) async {
        apiCalls.add('${o.method} ${o.path}');
        if (o.path.startsWith('/user')) {
          return Response<dynamic>(statusCode: 200, requestOptions: o, data: <String, dynamic>{});
        }
        if (o.method == 'GET') {
          throw DioException(requestOptions: o,
              response: Response<dynamic>(statusCode: 404, requestOptions: o));
        }
        return Response<dynamic>(statusCode: 201, requestOptions: o, data: <String, dynamic>{});
      }

      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubToken: 'ghp_test',
              githubRepo: 'Hoffnungsschimmers/mnscn',
              githubBranch: 'main',
            )),
        resultProvider.overrideWith((ref) => ResultNotifier()
          ..setRows([ResultRow('1.2.3.4:443#US mia', '50.00 ms')], 'addressesapi.txt')),
        githubPushProvider.overrideWith((ref) => (cfg) => GithubPush(
              token: cfg.githubToken,
              repo: cfg.githubRepo,
              branch: cfg.githubBranch,
              sender: fakeSender,
            )),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '推送 GitHub'));
      await tester.pumpAndSettle();

      expect(apiCalls, containsAll([
        'GET /user',
        'GET /repos/Hoffnungsschimmers/mnscn/contents/addressesapi.txt',
        'PUT /repos/Hoffnungsschimmers/mnscn/contents/addressesapi.txt',
      ]));
      expect(find.textContaining('推送成功'), findsOneWidget);
    });

    testWidgets('token 为空时提示且不发起推送', (tester) async {
      var builderCalled = false;
      final container = ProviderContainer(overrides: [
        configProvider.overrideWith((ref) async => const AppConfig(
              subOutputFile: 'addressesapi.txt',
              githubToken: '',
            )),
        resultProvider.overrideWith((ref) => ResultNotifier()
          ..setRows([ResultRow('1.2.3.4:443#US mia', '50.00 ms')], 'addressesapi.txt')),
        githubPushProvider.overrideWith((ref) => (cfg) {
              builderCalled = true;
              return GithubPush(token: 'x', repo: 'o/r',
                  sender: (o) async => Response<dynamic>(statusCode: 200, requestOptions: o));
            }),
      ]);
      addTearDown(container.dispose);
      await pumpResultsTab(tester, container: container);

      await tester.tap(find.widgetWithText(OutlinedButton, '推送 GitHub'));
      await tester.pump();

      expect(builderCalled, isFalse);
      expect(find.textContaining('GitHub Token'), findsOneWidget);
    });
  });
}
