import 'dart:convert';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/subscription/subscription_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = NodeParser(cnToCode: {'美国': 'US'}, alpha3ToAlpha2: {});

  group('decodeSubscription / resolveSubUrl', () {
    test('returns plaintext links as-is', () {
      const txt = 'vmess://abc\nvless://def';
      expect(decodeSubscription(txt), txt);
    });
    test('decodes base64 subscription', () {
      final b64 = base64UrlEncode(utf8.encode('vmess://abc123'));
      expect(decodeSubscription(b64), contains('vmess://'));
    });
    test('resolves sub:// share link', () {
      final inner = base64UrlEncode(utf8.encode('https://real.example.com/sub'));
      expect(resolveSubUrl('sub://$inner'), 'https://real.example.com/sub');
    });
    test('passes through normal url', () {
      expect(resolveSubUrl('https://x.com/a'), 'https://x.com/a');
    });
  });

  group('generatorFetchUrls', () {
    test('builds fallback urls', () {
      final cfg = AppConfig(subNodeHost: 'h.com', subNodeUuid: 'uuid-1');
      final urls = generatorFetchUrls('sub.example.com', cfg);
      expect(urls.length, 2);
      expect(urls[0], contains('/sub?host=h.com&uuid=uuid-1'));
      expect(urls[1], endsWith('/sub?token=auto'));
    });
    test('direct url mode returns as-is', () {
      final urls = generatorFetchUrls('https://sub.x.com/abcdef', const AppConfig());
      expect(urls, ['https://sub.x.com/abcdef']);
    });
    test('strips trailing slash before appending /sub', () {
      final cfg = AppConfig(subNodeHost: 'h.com', subNodeUuid: 'uuid-1');
      final urls = generatorFetchUrls('https://sub.example.com/', cfg);
      expect(urls[0], startsWith('https://sub.example.com/sub?'));
      expect(urls[0], isNot(contains('//sub?')));
    });
  });

  group('collectSubscriptionTasks', () {
    test('node mode collects generators, skips disabled', () {
      final cfg = AppConfig(
        subInputMode: 'node',
        subGenerators: const ['CM|sub.cm.com', 'IDK|sub.idk.com'],
        subDisabledGenerators: const {'IDK'},
      );
      final tasks = collectSubscriptionTasks(cfg);
      expect(tasks.length, 1);
      expect(tasks.first.$1, 'CM');
    });
    test('both mode merges node + url', () {
      final cfg = AppConfig(
        subInputMode: 'both',
        subGenerators: const ['CM|sub.cm.com'],
        subUrls: const ['https://my.sub/abcd'],
      );
      final tasks = collectSubscriptionTasks(cfg);
      expect(tasks.length, 2);
    });
  });

  group('fetchFirstWorking', () {
    test('returns first url that yields nodes, concurrently', () async {
      int callCount = 0;
      Future<String> fetcher(String url, {String label = ''}) async {
        callCount++;
        if (url.contains('fail')) return '';
        return 'vless://u@host.com:443';
      }
      final urls = ['https://a/fail', 'https://b/fail', 'https://c/ok'];
      final res = await fetchFirstWorking(urls, fetcher);
      expect(res, contains('vless://'));
      expect(callCount, 3); // 并发：全部发起
    });
  });

  group('convertSubscriptions', () {
    test('fetches, parses, resolves, dedups, maps source', () async {
      // 节点链接直接返回（无需抓取）
      Future<String?> fakeResolve(String host) async => host == 'node1.com' ? '1.1.1.1' : '2.2.2.2';

      const sub = 'vless://u@node1.com:443?remarks=%E7%BE%8E%E5%9B%BD#%E7%BE%8E%E5%9B%BD\n'
          'vless://u@node2.com:443#IDK';
      // 用直连 URL 模式注入内容
      // fetchSingle 对节点链接原样返回；但这里是 https url，会调用 fakeFetch(url)
      // 让它返回订阅明文：
      Future<String> fetchWithBody(String url, {String label = ''}) async => sub;

      final result = await convertSubscriptions(
        AppConfig(subInputMode: 'url', subUrls: const ['https://my.sub/abcd']),
        fetch: fetchWithBody,
        resolve: fakeResolve,
        parser: parser,
      );
      final nodes = result.nodes;
      expect(result.okSources, 1);
      expect(result.failedSources, 0);
      expect(nodes.length, 2);
      expect(nodes.any((n) => n.startsWith('1.1.1.1:443#US')), isTrue);
      // IDK 非真实国家码，按等价逻辑回落到默认国家 ''（无 # 后缀）
      expect(nodes.any((n) => n.startsWith('2.2.2.2:443')), isTrue);
      // 去重按 ip:port#cc：两个不同 host 解析到同一 IP 但端口/国家码可能不同，
      // 因此保留两条。仅同 ip:port#cc 才折叠为一条。
      final cfg2 = AppConfig(subInputMode: 'url', subUrls: const ['https://my.sub/abcd']);
      Future<String?> dupResolve(String host) async => '9.9.9.9';
      final nodes2 = (await convertSubscriptions(
        cfg2,
        fetch: fetchWithBody,
        resolve: dupResolve,
        parser: parser,
      )).nodes;
      expect(nodes2.length, 2);
    });

    test('全部源失败时统计失败源数', () async {
      Future<String> failingFetch(String url, {String label = ''}) async => '';

      final result = await convertSubscriptions(
        AppConfig(
          subInputMode: 'url',
          subUrls: const ['https://a.fail/sub', 'https://b.fail/sub'],
        ),
        fetch: failingFetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );

      expect(result.nodes, isEmpty);
      expect(result.okSources, 0);
      expect(result.failedSources, 2);
    });

    test('部分源失败时分别统计', () async {
      Future<String> partialFetch(String url, {String label = ''}) async =>
          url.contains('a.ok') ? 'vless://u@node1.com:443#US' : '';

      final result = await convertSubscriptions(
        AppConfig(
          subInputMode: 'url',
          subUrls: const ['https://a.ok/sub', 'https://b.fail/sub'],
        ),
        fetch: partialFetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );

      expect(result.nodes, isNotEmpty);
      expect(result.okSources, 1);
      expect(result.failedSources, 1);
    });
  });
}
