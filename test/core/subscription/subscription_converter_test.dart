import 'dart:convert';
import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/net/endpoint.dart';
import 'package:cfnb_app/core/subscription/subscription_converter.dart';
import 'package:cfnb_app/features/results/result_state.dart';
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
      // 只按 ip:port 去重：两行解析到不同 IP，各保留一条
      expect(nodes.length, 2);
      // 注释 = 国家码 + 来源名 + 原始节点备注
      expect(nodes, contains('1.1.1.1:443#US url 美国'));
      // IDK 提不出国家码：国家码位写占位码 UN，原始名留在备注里
      expect(nodes, contains('2.2.2.2:443#UN url IDK'));
      // 节点携带来源后缀，便于结果页/导出按源统计
      expect(nodes.every((n) => n.contains(' url')), isTrue);
      // 去重只看 ip:port：两个不同 host 解析到同一 IP 时折叠为一条。
      final cfg2 = AppConfig(subInputMode: 'url', subUrls: const ['https://my.sub/abcd']);
      Future<String?> dupResolve(String host) async => '9.9.9.9';
      final nodes2 = (await convertSubscriptions(
        cfg2,
        fetch: fetchWithBody,
        resolve: dupResolve,
        parser: parser,
      )).nodes;
      expect(nodes2.length, 1);
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

    test('默认国家码兜底无注释节点', () async {
      Future<String> fetch(String url, {String label = ''}) async =>
          'vless://u@node1.com:443';
      final result = await convertSubscriptions(
        AppConfig(
          subInputMode: 'url',
          subUrls: const ['https://a.ok/sub'],
          subDefaultCountry: 'jp',
        ),
        fetch: fetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      expect(result.nodes.length, 1);
      expect(result.nodes.first.startsWith('1.1.1.1:443#JP '), isTrue);
    });

    test('相同节点行去重', () async {
      Future<String> fetch(String url, {String label = ''}) async =>
          'vless://u@node1.com:443#US';
      final result = await convertSubscriptions(
        AppConfig(
          subInputMode: 'both',
          subGenerators: const ['G|sub.g.com'],
          subUrls: const ['https://a.ok/sub'],
        ),
        fetch: (url, {String label = ''}) async {
          // 订阅器候选 URL 均含 sub.g.com，统一返回同一节点行；
          // https 订阅链接返回另一份相同节点行 → 两源同 ip:port 只保留一条。
          if (url.contains('sub.g.com')) return 'vless://u@node1.com:443#US';
          return fetch(url, label: label);
        },
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      // 去重只按 ip:port：两源解析到同一 1.1.1.1:443 → 折叠为 1 条。
      expect(result.okSources, 2);
      expect(result.nodes.length, 1);
      // 保留首次出现那条（订阅器 G 先于 url），备注用它的来源名。
      expect(result.nodes, ['1.1.1.1:443#US G']);
    });

    test('同源完全相同行折叠', () async {
      Future<String> fetch(String url, {String label = ''}) async =>
          'vless://u@node1.com:443#US\nvless://u@node1.com:443#US';
      final result = await convertSubscriptions(
        AppConfig(
          subInputMode: 'url',
          subUrls: const ['https://a.ok/sub'],
        ),
        fetch: fetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      expect(result.nodes.length, 1);
    });

    test('注释保留原始节点备注', () async {
      // 原始名「美国 洛杉矶 01」：国家码进 # 首位，剩余原文留作备注。
      final link = 'vless://u@node1.com:443#${Uri.encodeComponent('美国 洛杉矶 01')}';
      Future<String> fetch(String url, {String label = ''}) async => link;
      final result = await convertSubscriptions(
        const AppConfig(subInputMode: 'url', subUrls: ['麒麟|https://a.ok/sub']),
        fetch: fetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      expect(result.nodes, ['1.1.1.1:443#US 麒麟 美国 洛杉矶 01']);
    });

    test('原始名自带来源名时注释不重复拼接', () async {
      // 订阅把源名写进了节点名（「麒麟 美国 洛杉矶」），来源只出现一次。
      final link = 'vless://u@node1.com:443#${Uri.encodeComponent('麒麟 美国 洛杉矶')}';
      Future<String> fetch(String url, {String label = ''}) async => link;
      final result = await convertSubscriptions(
        const AppConfig(subInputMode: 'url', subUrls: ['麒麟|https://a.ok/sub']),
        fetch: fetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      expect(result.nodes, ['1.1.1.1:443#US 麒麟 美国 洛杉矶']);
    });

    test('备注清洗：压缩空格，# 原样保留', () async {
      final link = 'vless://u@node1.com:443#${Uri.encodeComponent('美国  洛杉矶#01')}';
      Future<String> fetch(String url, {String label = ''}) async => link;
      final result = await convertSubscriptions(
        const AppConfig(subInputMode: 'url', subUrls: ['https://a.ok/sub']),
        fetch: fetch,
        resolve: (host) async => '1.1.1.1',
        parser: parser,
      );
      expect(result.nodes, ['1.1.1.1:443#US url 美国 洛杉矶#01']);
    });

    test('纯文本列表源同样保留原始备注', () async {
      // bestcf 类 txt 列表：# 后是国家码 + 原始备注；行内后续的 # 属备注原文，
      // 只有第一个 # 是结构性的。
      Future<String> fetch(String url, {String label = ''}) async =>
          '47.245.140.240:2087#US#洛杉矶-优化\n1.2.3.4#美国  圣何塞\n5.6.7.8:443#US#粤#Cloudflare#2';
      final result = await convertSubscriptions(
        const AppConfig(subInputMode: 'url', subUrls: ['速递|https://a.ok/sub']),
        fetch: fetch,
        resolve: (host) async => host,
        parser: parser,
      );
      expect(result.nodes, [
        '47.245.140.240:2087#US 速递 洛杉矶-优化',
        '1.2.3.4:443#US 速递 美国 圣何塞',
        '5.6.7.8:443#US 速递 粤#Cloudflare#2',
      ]);
    });
  });

  group('输出链路', () {
    test('获取 → 写文件 → 落地检测 → 结果页解析，备注全程不丢', () async {
      final localParser = NodeParser(
        cnToCode: {'美国': 'US', '德国': 'DE'},
        alpha3ToAlpha2: {},
      );
      final dir = await Directory.systemTemp.createTemp('cfnb_remark');
      addTearDown(() => dir.delete(recursive: true));
      final file = '${dir.path}${Platform.pathSeparator}addressesapi.txt';

      Future<String> fetch(String url, {String label = ''}) async => [
            'vless://u@node1.com:443#${Uri.encodeComponent('美国 洛杉矶 01')}',
            'vless://u@node2.com:2053#${Uri.encodeComponent('德国 法兰克福 03')}',
          ].join('\n');

      final conv = await convertSubscriptions(
        const AppConfig(subInputMode: 'url', subUrls: ['麒麟|https://a.ok/sub']),
        fetch: fetch,
        resolve: (h) async => h == 'node1.com' ? '1.1.1.1' : '2.2.2.2',
        parser: localParser,
      );
      await writeSubOutput(conv.nodes, file);

      expect(File(file).readAsLinesSync(), [
        '1.1.1.1:443#US 麒麟 美国 洛杉矶 01',
        '2.2.2.2:2053#DE 麒麟 德国 法兰克福 03',
      ]);

      // 落地检测按原始行改写国家码，备注不受影响。
      final lines = (await File(file).readAsLines())
          .map((e) => applyRealLanding(e, {'1.1.1.1': 'HK'}))
          .toList();
      expect(lines.first, '1.1.1.1:443#HK 麒麟 美国 洛杉矶 01');

      // 结果页解析：国家码仍取注释首位，来源列 = 来源名 + 原始备注。
      final row = parseResultLines(lines.join('\n')).first;
      expect(row.ipPort, '1.1.1.1:443');
      expect(nodeCountry(row.node), 'HK');
      expect(row.source, '麒麟 美国 洛杉矶 01');
      // 再写回（结果页保存路径）内容仍然一致。
      expect(ResultState(rows: parseResultLines(lines.join('\n'))).toText().trimRight(),
          lines.join('\n'));
    });
  });
}
