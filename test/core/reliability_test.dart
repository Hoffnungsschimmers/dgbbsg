import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:cfnb_app/core/logging/app_logger.dart';
import 'package:cfnb_app/core/net/geo_cache.dart';
import 'package:cfnb_app/core/net/http_fetcher.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:cfnb_app/core/net/push_quality.dart';
import 'package:cfnb_app/core/net/task_cancel.dart';
import 'package:cfnb_app/core/storage/result_files.dart';
import 'package:cfnb_app/core/storage/safe_file.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  final String dir;
  _Paths(this.dir);
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

class _RealHttp extends HttpOverrides {}

class _FailingAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    calls++;
    return ResponseBody.fromString('unavailable', 503);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late PathProviderPlatform paths;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cfnb_reliability_');
    paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = paths;
    await dir.delete(recursive: true);
  });

  test('推送门槛区分实测与估计，并识别数量骤减', () {
    expect(
      pushQualityIssue(nodes: 100, totalIps: 100, measured: 1, estimated: 99),
      contains('实测'),
    );
    expect(
      pushQualityIssue(
        nodes: 10,
        totalIps: 10,
        measured: 10,
        estimated: 0,
        previousNodes: 100,
      ),
      contains('减少'),
    );
    expect(
      pushQualityIssue(
        nodes: 50,
        totalIps: 10,
        measured: 5,
        estimated: 5,
        previousNodes: 100,
      ),
      isNull,
    );
    expect(
      pushQualityIssue(nodes: 0, totalIps: 0, measured: 0, estimated: 0),
      isNotNull,
    );
  });

  test('GeoIP 缓存过期、未来时间和旧格式均不沿用', () {
    final now = DateTime.utc(2026, 10, 2);
    final cache = GeoCache.decode(
      jsonEncode({
        'old': 'US',
        'expired': {
          'country': 'US',
          'at': now.subtract(const Duration(days: 8)).toIso8601String(),
        },
        'future': {
          'country': 'JP',
          'at': now.add(const Duration(days: 1)).toIso8601String(),
        },
        'fresh': {
          'country': 'HK',
          'at': now.subtract(const Duration(days: 1)).toIso8601String(),
        },
      }),
      now: now,
    );
    expect(cache.countries, {'fresh': 'HK'});
    final oldAt = cache.timestamps['fresh'];
    cache.addAll({'new': 'SG'}, now: now);
    expect(
      GeoCache.decode(cache.encode(), now: now).timestamps['fresh'],
      oldAt,
    );
  });

  test('取消立即结束退避，不再发起重试', () async {
    final cancel = TaskCancel();
    final token = CancelToken();
    cancel.register(() => token.cancel());
    final adapter = _FailingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final sleeping = Completer<void>();
    final future = fetchHttpWithRetry(
      dio: dio,
      url: 'https://test.invalid/private?token=secret',
      connectTimeoutSec: 1,
      sendTimeoutSec: 1,
      receiveTimeoutSec: 1,
      maxRetries: 3,
      retryDelayMs: 60000,
      cancelToken: token,
      sleep: (duration) {
        sleeping.complete();
        return cancel.delay(duration);
      },
    );
    final assertion = expectLater(future, throwsA(isA<TaskCancelled>()));
    await sleeping.future;
    cancel.cancel();
    await assertion;
    expect(adapter.calls, 1);
    dio.close(force: true);
  });

  test('安全写恢复中断替换，结果哈希拒绝不匹配的证据', () async {
    final file = File('${dir.path}/result.txt');
    await File('${file.path}.previous').writeAsString('old');
    await recoverSafeFile(file);
    expect(await file.readAsString(), 'old');
    await writeResultBundle(file, '1.1.1.1:443#HK\n', {
      'landing_evidence': {'1.1.1.1': 'cloudflare_trace'},
    });
    expect(
      (await readResultMeta(
        file,
        await file.readAsString(),
      ))['landing_evidence'],
      isNotEmpty,
    );
    await safeWriteText(file, '2.2.2.2:443#US\n');
    expect(await readResultMeta(file, await file.readAsString()), isEmpty);
  });

  test('取消关闭正在等待响应的 trace 请求', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<void>();
    server.listen((request) {
      if (!received.isCompleted) received.complete();
      // Deliberately leave the response open to verify cancellation, not timeout.
    });
    addTearDown(() => server.close(force: true));
    final cancel = TaskCancel();
    final future = geolocateCfIp(
      '127.0.0.1:${server.port}',
      timeout: const Duration(seconds: 30),
      cancel: cancel,
    );
    final assertion = expectLater(
      future.timeout(const Duration(seconds: 1)),
      throwsA(isA<TaskCancelled>()),
    );
    await received.future.timeout(const Duration(seconds: 2));
    cancel.cancel();
    await assertion;
    }, _RealHttp());
  });

  test('同一结果并发保存保持文本与证据一致', () async {
    final file = File('${dir.path}/result.txt');
    await Future.wait([
      writeResultBundle(file, 'A', {'round': 1}),
      writeResultBundle(file, 'B', {'round': 2}),
    ]);
    expect(await file.readAsString(), 'B');
    expect((await readResultMeta(file, 'B'))['round'], 2);
  });

  test('恢复快照保留证据，并备份恢复前的结果', () async {
    final file = File('${dir.path}/result_top.txt');
    await writeResultBundle(file, '1.1.1.1:443#HK\n', {
      'landing_evidence': {'1.1.1.1': 'cloudflare_trace'},
    });
    await writeResultBundle(file, '2.2.2.2:443#US\n', {
      'landing_evidence': {'2.2.2.2': 'ip_geo_database'},
    });
    final notifier = ResultNotifier();
    addTearDown(notifier.dispose);
    await notifier.loadFile(file.path);
    final snapshots = await notifier.snapshots();
    expect(snapshots, hasLength(1));
    await notifier.restoreSnapshot(snapshots.single);
    expect(notifier.state.rows.single.ipPort, '1.1.1.1:443');
    expect(notifier.state.rows.single.evidenceLabel, 'POP 实测');
    expect(await notifier.snapshots(), hasLength(2));
  });

  test('日志在内存、磁盘和导出中均脱敏', () async {
    final logger = AppLogger();
    await logger.enablePersistence(Directory('${dir.path}/logs'));
    logger.registerSecrets(['private-key-value']);
    logger.info(
      'private-key-value https://user:pass@host.test/private/path?token=abc Bearer abcdef',
    );
    await logger.flush();
    final exported = File('${dir.path}/diagnostics.log');
    await logger.exportTo(exported);
    final disk = await Directory(
      '${dir.path}/logs',
    ).listSync().whereType<File>().single.readAsString();
    for (final content in [
      logger.snapshot.join(),
      disk,
      await exported.readAsString(),
    ]) {
      for (final secret in [
        'private-key-value',
        'user:pass',
        '/private/path',
        'abcdef',
      ]) {
        expect(content, isNot(contains(secret)));
      }
    }
    logger.dispose();
  });

  test('损坏配置不阻塞启动；并发保存以最后一次为准', () async {
    SharedPreferences.setMockInitialValues({'app_config_json': '{broken'});
    final secure = InMemorySecureKv();
    final repo = await ConfigRepository.init(secure: secure);
    expect(repo.current.subOutputFile, 'addressesapi.txt');
    await Future.wait([
      repo.save(const AppConfig(githubToken: 'first', githubBranch: 'first')),
      repo.save(const AppConfig(githubToken: 'last', githubBranch: 'last')),
    ]);
    final reloaded = await ConfigRepository.init(secure: secure);
    expect(reloaded.current.githubBranch, 'last');
    expect(reloaded.current.githubToken, 'last');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'app_config_corrupt_backup',
      ),
      '{broken',
    );
  });

  test('GitHub 目标分支 SHA 冲突后重读；无关 422 不重试', () async {
    var gets = 0;
    var puts = 0;
    final gh = GithubPush(
      token: 'fake',
      repo: 'a/b',
      branch: 'test/branch',
      sender: (o) async {
        if (o.path == '/user')
          return Response(statusCode: 200, requestOptions: o);
        if (o.method == 'GET') {
          gets++;
          expect(o.path, endsWith('?ref=test%2Fbranch'));
          return Response(
            statusCode: 200,
            requestOptions: o,
            data: {'sha': 'sha$gets'},
          );
        }
        puts++;
        expect(o.path, isNot(contains('?ref=')));
        expect(o.data['branch'], 'test/branch');
        expect(o.data['sha'], 'sha$gets');
        return Response(statusCode: puts == 1 ? 409 : 200, requestOptions: o);
      },
    );
    expect(await gh.pushFile('result_top.txt', 'content'), 200);
    expect(gets, 2);
    expect(puts, 2);
    puts = 0;
    final invalid = GithubPush(
      token: 'fake',
      repo: 'a/b',
      sender: (o) async {
        if (o.method == 'PUT') {
          puts++;
          return Response(
            statusCode: 422,
            requestOptions: o,
            data: {'message': 'invalid branch'},
          );
        }
        return Response(
          statusCode: 200,
          requestOptions: o,
          data: {'sha': 'sha'},
        );
      },
    );
    await expectLater(
      invalid.pushFile('result_top.txt', 'content'),
      throwsException,
    );
    expect(puts, 1);
  });
}
