import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/subscriptions/run_tab.dart';
import 'package:cfnb_app/features/subscriptions/subscriptions_state.dart';

void main() {
  test('一键全流程：订阅没产出节点时中止，不跑落地检测也不推送', () async {
    // 注意：notifier 的配置来自 ConfigRepository（_cfg 优先 latestConfigProvider，
    // 回落 repo.current），空 prefs 会回落到「默认 10 个订阅器 + both」并真去发请求。
    // 所以这里必须把「无来源」的配置种进 prefs，才能让转换产出 0 节点。
    SharedPreferences.setMockInitialValues({
      'flutter.app_config_json': jsonEncode({
        'SUB_INPUT_MODE': 'url',
        'SUB_URLS': <String>[],
        'SUB_GENERATORS': <String>[],
      }),
    });
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    final container = ProviderContainer(overrides: [
      configRepositoryProvider.overrideWith((ref) => repo),
      configProvider.overrideWith((ref) async => repo.current),
      nodeParserProvider.overrideWith(
          (ref) async => NodeParser(cnToCode: const {'美国': 'US'}, alpha3ToAlpha2: const {})),
      // 容器销毁时 StateNotifier.dispose 会被调用两次（debug 断言），与 app_test 同样处理
      subProvider.overrideWith((ref) => _SafeSubNotifier(ref)),
    ]);
    addTearDown(container.dispose);
    final logger = container.read(subLoggerProvider);

    await container.read(subProvider.notifier).runPipeline();

    final logs = logger.snapshot.join('\n');
    expect(logs, contains('一键全流程：获取订阅 → 测落地 → 推送'));
    expect(logs, contains('订阅转换没有产出节点'));
    // 中止后不应进入落地检测（落地检测会去读结果文件）
    expect(logs, isNot(contains('开始落地检测')));
    expect(container.read(resultProvider).rows, isEmpty);
    // 状态必须被清干净，不能卡在 running
    expect(container.read(subProvider).running, isFalse);
    expect(container.read(subProvider).currentAction, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  testWidgets('运行页有「一键全流程」按钮，点击即调用 runPipeline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = await ConfigRepository.init(secure: InMemorySecureKv());
    final container = ProviderContainer(overrides: [
      configRepositoryProvider.overrideWith((ref) => repo),
      configProvider.overrideWith((ref) async => const AppConfig()),
      subProvider.overrideWith((ref) => _RecordingNotifier(ref)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: RunTab())),
    ));
    await tester.pumpAndSettle();

    final recorder = container.read(subProvider.notifier) as _RecordingNotifier;
    expect(find.text('一键全流程'), findsOneWidget);
    await tester.tap(find.text('一键全流程'));
    await tester.pumpAndSettle();

    expect(recorder.pipelineCalls, 1);
    // 单步按钮仍在，说明全流程是新增入口而非替换掉手动步骤
    expect(find.text('获取订阅'), findsOneWidget);
    expect(find.text('测落地'), findsOneWidget);
  });
}

/// 容器销毁时 StateNotifier.dispose 会被调用两次（debug 断言），故屏蔽 super.dispose。
class _SafeSubNotifier extends SubscriptionsNotifier {
  _SafeSubNotifier(super.ref);

  @override
  // ignore: must_call_super  // 诊断落在方法声明行，注释必须紧贴它
  void dispose() {
    stopAutoUpdate();
  }
}

/// 只记录调用次数的假 notifier：覆盖 runPipeline，避免真发网络请求。
class _RecordingNotifier extends SubscriptionsNotifier {
  _RecordingNotifier(super.ref);

  int pipelineCalls = 0;

  @override
  Future<void> runPipeline() async {
    pipelineCalls++;
  }

  @override
  // ignore: must_call_super  // StateNotifier.dispose 非幂等，容器销毁会二次调用
  void dispose() {
    stopAutoUpdate();
  }
}
