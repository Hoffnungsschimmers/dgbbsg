import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:cfnb_app/core/logging/app_logger.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:cfnb_app/core/storage/result_files.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/subscriptions/subscriptions_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers/temp_dir.dart';

class _Paths extends PathProviderPlatform {
  final String dir;
  _Paths(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

class _Adapter implements HttpClientAdapter {
  String body = '1.1.1.1:443#HK\n2.2.2.2:443#US\n';
  void Function()? onFetch;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    onFetch?.call();
    return ResponseBody.fromString(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform oldPaths;
  late ConfigRepository repo;
  late _Adapter adapter;
  var pushCalls = 0;
  var probeCalls = 0;
  AppConfig? pushedConfig;
  const cfg = AppConfig(
    subInputMode: 'url',
    subUrls: ['https://fake.invalid/sub'],
    subGenerators: [],
    subResolveDomain: false,
    githubToken: 'fake-token',
    githubRepo: 'test/results',
  );

  Future<ProviderContainer> makeContainer({
    bool estimated = false,
    Completer<void>? landingStarted,
    Completer<CfLanding?>? pending,
  }) async {
    final container = ProviderContainer(
      overrides: [
        configRepositoryProvider.overrideWith((ref) => repo),
        configProvider.overrideWith((ref) async => repo.current),
        subLoggerProvider.overrideWith((ref) {
          final logger = AppLogger();
          ref.onDispose(logger.dispose);
          return logger;
        }),
        nodeParserProvider.overrideWith(
          (ref) async => NodeParser(
            cnToCode: const {'香港': 'HK', '美国': 'US'},
            alpha3ToAlpha2: const {},
          ),
        ),
        subscriptionDioProvider.overrideWith(
          (ref) =>
              (_) => Dio()..httpClientAdapter = adapter,
        ),
        egressProbeProvider.overrideWith(
          (ref) =>
              (_) async => const EgressInfo(ip: '9.9.9.9', colo: 'HKG'),
        ),
        landingProbeProvider.overrideWith(
          (ref) => (ip, cancel) async {
            probeCalls++;
            if (landingStarted != null && !landingStarted.isCompleted)
              landingStarted.complete();
            if (pending != null) return pending.future;
            if (estimated) return null;
            return CfLanding(
              ip: ip,
              airport: 'HKG',
              country: 'HK',
              trace: 'colo=HKG',
            );
          },
        ),
        geoProbeProvider.overrideWith(
          (ref) =>
              (ips, _) async => {for (final ip in ips) ip: 'US'},
        ),
        githubPushProvider.overrideWith(
          (ref) => (config) {
            pushedConfig = config;
            return GithubPush(
              token: config.githubToken,
              repo: config.githubRepo,
              branch: config.githubBranch,
              sender: (o) async {
                if (o.method == 'PUT') {
                  pushCalls++;
                  return Response(statusCode: 201, requestOptions: o);
                }
                return Response(
                  statusCode: o.path == '/user' ? 200 : 404,
                  requestOptions: o,
                );
              },
            );
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await ConfigRepository.init(secure: InMemorySecureKv());
    await repo.save(cfg);
    dir = await Directory.systemTemp.createTemp('cfnb_pipeline_');
    oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    adapter = _Adapter();
    pushCalls = 0;
    probeCalls = 0;
    pushedConfig = null;
  });
  tearDown(() async {
    PathProviderPlatform.instance = oldPaths;
    await removeTempDir(dir);
  });

  test('失败时保留旧结果，不继续检测或推送', () async {
    adapter.body = '';
    final container = await makeContainer();
    container.read(resultProvider.notifier).setRows([
      ResultRow('8.8.8.8:443#US'),
    ]);
    await container.read(subProvider.notifier).runPipeline();
    expect(probeCalls, 0);
    expect(pushCalls, 0);
    expect(container.read(resultProvider).rows.single.ipPort, '8.8.8.8:443');
    expect(container.read(subProvider).running, isFalse);
    expect(container.read(subProvider).succeeded, isFalse);
  });

  test('仅 GeoIP 估计保存结果但阻止自动推送', () async {
    final container = await makeContainer(estimated: true);
    await container.read(subProvider.notifier).runPipeline();
    expect(pushCalls, 0);
    expect(container.read(subProvider).summary, contains('拦截'));
    expect(
      container
          .read(resultProvider)
          .rows
          .every((r) => r.evidenceLabel == 'GeoIP 估计'),
      isTrue,
    );
    expect(File('${dir.path}/addressesapi_top.txt').existsSync(), isTrue);
  });

  test('流水线配置固定，运行中修改只作用于下一轮', () async {
    final container = await makeContainer();
    adapter.onFetch = () {
      container.read(latestConfigProvider.notifier).state = cfg.copyWith(
        githubRepo: 'changed/repo',
        githubBranch: 'other',
        landingOutputFile: 'other_top.txt',
      );
    };
    final stages = <String>[];
    container.listen(subProvider, (_, next) => stages.add(next.stage));
    await container.read(subProvider.notifier).runPipeline();
    expect(pushCalls, 1);
    expect(pushedConfig?.githubRepo, 'test/results');
    expect(pushedConfig?.githubBranch, 'main');
    expect(File('${dir.path}/addressesapi_top.txt').existsSync(), isTrue);
    expect(File('${dir.path}/other_top.txt').existsSync(), isFalse);
    expect(stages, containsAll(['获取订阅', 'POP 实测', '保存检测结果', '推送 GitHub']));
    expect(container.read(subProvider).succeeded, isTrue);
  });

  test('检测中取消及时结束，旧落地输出不被覆盖，不能插入第二个任务', () async {
    final file = File('${dir.path}/addressesapi_top.txt');
    await writeResultBundle(file, '8.8.8.8:443#US\n', {});
    final started = Completer<void>();
    final pending = Completer<CfLanding?>();
    final container = await makeContainer(
      landingStarted: started,
      pending: pending,
    );
    final notifier = container.read(subProvider.notifier);
    final pipeline = notifier.runPipeline();
    await started.future;
    expect(await notifier.runLandingCheck(), (0, 0));
    await notifier.runSubscription();
    notifier.cancel();
    await pipeline.timeout(const Duration(seconds: 1));
    expect(pushCalls, 0);
    expect(await file.readAsString(), '8.8.8.8:443#US\n');
    expect(container.read(subProvider).summary, contains('已取消'));
    expect(container.read(subProvider).running, isFalse);
    pending.complete(null);
  });

  test('数量骤减被拦截；再次运行不能绕过上次推送基线', () async {
    final file = File('${dir.path}/addressesapi_top.txt');
    await writeResultBundle(
      file,
      List.generate(20, (i) => '10.0.0.${i + 1}:443#US').join('\n'),
      {},
    );
    final container = await makeContainer();
    await container.read(subProvider.notifier).runPipeline();
    expect(pushCalls, 0);
    expect(container.read(subProvider).summary, contains('减少'));
    await container.read(subProvider.notifier).runPipeline();
    expect(pushCalls, 0);
    expect(container.read(subProvider).summary, contains('减少'));
  });

  test('自动更新按模式执行，备份占用时跳过', () async {
    final container = await makeContainer();
    container.read(latestConfigProvider.notifier).state = cfg.copyWith(
      subAutoUpdateEnabled: true,
      subAutoUpdateMode: 'landing',
    );
    final notifier = container.read(subProvider.notifier);
    await notifier.runScheduledUpdate();
    expect(probeCalls, 2);
    expect(pushCalls, 0);
    container.read(latestConfigProvider.notifier).state = cfg.copyWith(
      subAutoUpdateEnabled: true,
      subAutoUpdateMode: 'pipeline',
    );
    await notifier.runScheduledUpdate();
    expect(pushCalls, 1);
    container.read(webDavBusyProvider.notifier).state = true;
    await notifier.runScheduledUpdate();
    expect(pushCalls, 1);
  });
}
