import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/webdav/webdav_client.dart';
import 'package:cfnb_app/core/webdav/webdav_sync.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_test/flutter_test.dart';

/// 内存 WebDAV 适配器：PUT 存字节、GET 返回或 404，记录请求与认证头。
class _MemAdapter implements dio_pkg.HttpClientAdapter {
  final files = <String, List<int>>{};
  final requests = <dio_pkg.RequestOptions>[];

  @override
  Future<dio_pkg.ResponseBody> fetch(
    dio_pkg.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'PUT') {
      final bytes = <int>[];
      if (requestStream != null) {
        await requestStream.listen(bytes.addAll).asFuture();
      }
      files[options.path] = bytes;
      return dio_pkg.ResponseBody.fromString('', 201);
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

WebDavClient _client(_MemAdapter adapter, {String base = 'https://dav.test/dav'}) {
  return WebDavClient(
    baseUrl: base,
    user: 'user1',
    password: 'pass1',
    dio: dio_pkg.Dio()..httpClientAdapter = adapter,
  );
}

String _key(String name, {String base = 'https://dav.test/dav'}) {
  return '$base/$name';
}

void main() {
  group('WebDavClient', () {
    test('PUT 带 Basic Auth 头并携带文件内容', () async {
      final adapter = _MemAdapter();
      final client = _client(adapter);
      await client.upload('backup/a.txt', utf8.encode('hello'));

      expect(adapter.requests, hasLength(1));
      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(
        req.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('user1:pass1'))}',
      );
      expect(req.path, 'https://dav.test/dav/backup/a.txt');
      expect(utf8.decode(adapter.files[_key('backup/a.txt')]!), 'hello');
    });

    test('GET 返回内容，缺失文件抛 WebDavNotFoundException', () async {
      final adapter = _MemAdapter()..files[_key('x.bin')] = [1, 2, 3];
      final client = _client(adapter);
      expect(await client.download('x.bin'), [1, 2, 3]);

      expect(
        () => client.download('missing.bin'),
        throwsA(isA<WebDavNotFoundException>()),
      );
    });

    test('baseUrl 尾部斜杠与路径头斜杠归一化', () async {
      final adapter = _MemAdapter();
      final client = _client(adapter, base: 'https://dav.test/dav/');
      await client.upload('/a/b.txt', utf8.encode('x'));
      expect(adapter.requests.single.path, 'https://dav.test/dav/a/b.txt');
    });
  });

  group('WebDavSync', () {
    test('resultFileNames 汇总输出文件/当前文件并带 .json 旁文件、去重排序', () {
      const cfg = AppConfig(
        subOutputFile: 'addressesapi.txt',
        subLatencyOutputFile: 'addressesapi_top.txt',
      );
      final names = WebDavSync.resultFileNames(cfg, 'addressesapi.txt');
      expect(
        names,
        [
          'addressesapi.txt',
          'addressesapi.txt.json',
          'addressesapi_top.txt',
          'addressesapi_top.txt.json',
        ],
      );
    });

    test('fullConfigJson 含敏感字段（token/webhook/webdav 密码）', () {
      const cfg = AppConfig(
        githubToken: 'tok',
        webhookUrl: 'https://hook.test/x',
        webdavPassword: 'wd-pass',
      );
      final m = WebDavSync.fullConfigJson(cfg);
      expect(m['GITHUB_TOKEN'], 'tok');
      expect(m['WEBHOOK_URL'], 'https://hook.test/x');
      expect(m['WEBDAV_PASSWORD'], 'wd-pass');
    });

    test('配置备份与恢复往返（含敏感字段）', () async {
      final adapter = _MemAdapter();
      final client = _client(adapter);
      const cfg = AppConfig(
        githubRepo: 'a/b',
        subLatencyTopN: 7,
        githubToken: 'secret-token',
        webdavPassword: 'wd-secret',
      );
      await WebDavSync.backupConfig(client, cfg);

      final restored = await WebDavSync.restoreConfig(client);
      expect(restored.githubRepo, 'a/b');
      expect(restored.subLatencyTopN, 7);
      expect(restored.githubToken, 'secret-token');
      expect(restored.webdavPassword, 'wd-secret');
    });

    test('备份结果：仅上传本地存在的文件', () async {
      final adapter = _MemAdapter();
      final client = _client(adapter);
      final dir = await Directory.systemTemp.createTemp('webdav_backup_');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/a.txt').writeAsStringSync('AAA');

      final uploaded = await WebDavSync.backupResults(
        client,
        dir.path,
        ['a.txt', 'missing.txt', 'a.txt.json'],
      );
      expect(uploaded, ['a.txt']);
      expect(utf8.decode(adapter.files[_key('a.txt')]!), 'AAA');
      expect(adapter.files.containsKey(_key('missing.txt')), isFalse);
    });

    test('恢复结果：404 跳过、成功写回本地', () async {
      final adapter = _MemAdapter();
      adapter.files[_key('a.txt')] = utf8.encode('AAA');
      adapter.files[_key('a.txt.json')] = utf8.encode('{"a":1}');
      final client = _client(adapter);
      final dir = await Directory.systemTemp.createTemp('webdav_restore_');
      addTearDown(() => dir.delete(recursive: true));

      final restored = await WebDavSync.restoreResults(
        client,
        dir.path,
        ['a.txt', 'missing.txt', 'a.txt.json'],
      );
      expect(restored, ['a.txt', 'a.txt.json']);
      expect(File('${dir.path}/a.txt').readAsStringSync(), 'AAA');
      expect(
        jsonDecode(File('${dir.path}/a.txt.json').readAsStringSync()),
        {'a': 1},
      );
    });
  });
}