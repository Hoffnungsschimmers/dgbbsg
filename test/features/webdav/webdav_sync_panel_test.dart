import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/config/config_repository.dart';
import 'package:cfnb_app/core/config/secure_kv.dart';
import 'package:cfnb_app/core/webdav/webdav_client.dart';
import 'package:cfnb_app/features/webdav/webdav_sync_panel.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemAdapter implements dio_pkg.HttpClientAdapter {
  final files = <String, List<int>>{};
  int putStatus = 201;

  @override
  Future<dio_pkg.ResponseBody> fetch(
    dio_pkg.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'PUT') {
      if (putStatus >= 400) return dio_pkg.ResponseBody.fromString('', putStatus);
      final bytes = <int>[];
      if (requestStream != null) {
        await requestStream.listen(bytes.addAll).asFuture();
      }
      files[options.path] = bytes;
      return dio_pkg.ResponseBody.fromString('', putStatus);
    }
    if (options.method == 'GET') {
      final b = files[options.path];
      if (b == null) return dio_pkg.ResponseBody.fromString('', 404);
      return dio_pkg.ResponseBody.fromBytes(Uint8List.fromList(b), 200);
    }
    return dio_pkg.ResponseBody.fromString('', 405);
  }

  @override
  void close({bool force = false}) {}
}

class _FakePathProvider extends PathProviderPlatform {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

void main() {
  late ConfigRepository repo;

  Future<void> pumpApp(
    WidgetTester tester, {
    AppConfig? cfg,
    _MemAdapter? adapter,
  }) async {
    SharedPreferences.setMockInitialValues({});
    repo = await ConfigRepository.init(secure: InMemorySecureKv());
    final syncCfg = cfg ?? const AppConfig();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        configRepositoryProvider.overrideWith((ref) => repo),
        configProvider.overrideWith((ref) async => syncCfg),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              Consumer(
                builder: (context, ref, _) => IconButton(
                  icon: const Icon(Icons.cloud_sync_outlined),
                  onPressed: () => showWebDavSyncSheet(context, ref,
                      clientBuilder: (c) {
                    final dio = dio_pkg.Dio()
                      ..httpClientAdapter = adapter ?? _MemAdapter();
                    return WebDavClient(
                      baseUrl: 'https://dav.test/dav',
                      user: 'u',
                      password: 'p',
                      dio: dio,
                    );
                  }),
                ),
              ),
            ],
          ),
          body: const SizedBox(),
        ),
      ),
    ));
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    container.read(latestConfigProvider.notifier).state = syncCfg;
    await tester.pumpAndSettle();
  }

  testWidgets('未配置 WebDAV 时点击同步按钮提示先配置', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pump();
    expect(find.text('请先在「配置」页填写 WebDAV 服务器地址与账号'), findsOneWidget);
    expect(find.text('同步配置'), findsNothing);
    expect(find.text('同步结果'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同步菜单含「同步配置」「同步结果」两项，取消可退出', (tester) async {
    await pumpApp(tester, cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'));

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    expect(find.text('同步配置'), findsOneWidget);
    expect(find.text('同步结果'), findsOneWidget);

    await tester.tap(find.text('同步结果'));
    await tester.pumpAndSettle();
    expect(find.text('推送备份'), findsOneWidget);
    expect(find.text('拉取恢复'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('推送备份'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同步配置-推送备份 上传配置并提示', (tester) async {
    final adapter = _MemAdapter();
    await pumpApp(
      tester,
      cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'),
      adapter: adapter,
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推送备份'));
    await tester.pumpAndSettle();

    expect(find.text('配置已备份到 WebDAV'), findsOneWidget);
    expect(
      adapter.files.containsKey('https://dav.test/dav/cfnb_config.json'),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同步配置-拉取恢复 经注入客户端把配置写回仓库', (tester) async {
    final adapter = _MemAdapter()
      ..files['https://dav.test/dav/cfnb_config.json'] = utf8.encode(
        jsonEncode(const AppConfig(subDefaultCountry: 'DE', subLatencyTopN: 9)
            .toJson()),
      );
    await pumpApp(
      tester,
      cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'),
      adapter: adapter,
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拉取恢复'));
    await tester.pumpAndSettle();

    expect(find.text('配置已从 WebDAV 恢复'), findsOneWidget);
    final saved = repo.current;
    expect(saved.subDefaultCountry, 'DE');
    expect(saved.subLatencyTopN, 9);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('同步结果-拉取恢复 云盘无文件时跳过并提示', (tester) async {
    // 注：真实文件写回已由 webdav_sync_test（普通 test）覆盖；
    // testWidgets 的 fake async zone 中 dart:io 真实 IO 会挂起，
    // 此处用 404 全跳过场景验证 UI 流程闭环。
    final dir = await tester.runAsync(
            () => Directory.systemTemp.createTemp('cfnb_webdav_ui')) ??
        Directory.systemTemp;
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    final adapter = _MemAdapter(); // 云盘为空 → 全部 404
    await pumpApp(
      tester,
      cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'),
      adapter: adapter,
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拉取恢复'));
    await tester.pumpAndSettle();

    expect(find.text('已恢复 0 个结果文件'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拉取配置但云盘无备份时给出友好提示', (tester) async {
    await pumpApp(
      tester,
      cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'),
      adapter: _MemAdapter(), // 云盘为空 → cfnb_config.json 404
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拉取恢复'));
    await tester.pumpAndSettle();

    expect(find.text('云盘上没有备份文件（404），请先推送备份'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('推送配置但服务器 404（目录不存在）给出明确提示', (tester) async {
    final adapter = _MemAdapter()..putStatus = 404;
    await pumpApp(
      tester,
      cfg: const AppConfig(webdavUrl: 'https://dav.test/dav', webdavUser: 'u'),
      adapter: adapter,
    );

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步配置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推送备份'));
    await tester.pumpAndSettle();

    expect(
      find.text('目标路径不存在（404）：请检查服务器地址，或先在云盘创建对应目录'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}