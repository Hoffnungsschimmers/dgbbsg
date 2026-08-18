import 'dart:convert';

import 'package:cfnb_app/core/export/config_generator.dart';
import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 构建测试用 ResultRow 列表（SS / VMess / Trojan 各一个）。
  List<ResultRow> _makeRows() => [
        ResultRow('1.2.3.4:443#US CM', '50.00 ms'),
        ResultRow('10.0.0.1:8080#HK VMess', '120.50ms'),
        ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms'),
      ];

  // =========================================================================
  // FullConfigFormat enum
  // =========================================================================

  group('FullConfigFormat', () {
    test('label 返回正确的中文标签', () {
      expect(FullConfigFormat.clash.label, 'Clash 配置');
      expect(FullConfigFormat.singbox.label, 'sing-box 配置');
      expect(FullConfigFormat.v2ray.label, 'V2Ray 配置');
    });

    test('icon 返回非 null 的 IconData', () {
      expect(FullConfigFormat.clash.icon, isNotNull);
      expect(FullConfigFormat.singbox.icon, isNotNull);
      expect(FullConfigFormat.v2ray.icon, isNotNull);
    });

    test('fileExtension 返回正确的扩展名', () {
      expect(FullConfigFormat.clash.fileExtension, '.yaml');
      expect(FullConfigFormat.singbox.fileExtension, '.json');
      expect(FullConfigFormat.v2ray.fileExtension, '.json');
    });

    test('枚举值共 3 个', () {
      expect(FullConfigFormat.values.length, 3);
    });
  });

  // =========================================================================
  // generateClashConfig
  // =========================================================================

  group('generateClashConfig', () {
    test('输出包含基础设置字段', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('port: 7890'));
      expect(yaml, contains('socks-port: 7891'));
      expect(yaml, contains('allow-lan: true'));
      expect(yaml, contains('mode: rule'));
      expect(yaml, contains('log-level: info'));
    });

    test('输出包含 proxies: 段', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('proxies:'));
      // 每个节点应出现
      expect(yaml, contains('1.2.3.4'));
      expect(yaml, contains('10.0.0.1'));
      expect(yaml, contains('2001:db8::1'));
    });

    test('输出包含三个 proxy-groups', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('proxy-groups:'));
      expect(yaml, contains('🚀 节点选择'));
      expect(yaml, contains('♻️ 自动选择'));
      expect(yaml, contains('🐟 漏网之鱼'));
    });

    test('自动选择组配置正确', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('type: url-test'));
      expect(yaml, contains('url: http://www.gstatic.com/generate_204'));
      expect(yaml, contains('interval: 300'));
    });

    test('漏网之鱼包含 DIRECT 和其他组', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('      - DIRECT'));
      expect(yaml, contains('      - "🚀 节点选择"'));
      expect(yaml, contains('      - "♻️ 自动选择"'));
    });

    test('输出包含基本 rules', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, contains('rules:'));
      expect(yaml, contains('DOMAIN-SUFFIX,cn,DIRECT'));
      expect(yaml, contains('DOMAIN-KEYWORD,google,🚀 节点选择'));
      expect(yaml, contains('DOMAIN-KEYWORD,github,🚀 节点选择'));
      expect(yaml, contains('GEOIP,CN,DIRECT'));
      expect(yaml, contains('MATCH,🐟 漏网之鱼'));
    });

    test('subUrl 参数注入订阅地址', () {
      final yaml = ConfigGenerator.generateClashConfig(
        _makeRows(),
        subUrl: 'https://example.com/sub',
      );
      expect(yaml, contains('sub-url: "https://example.com/sub"'));
    });

    test('subUrl 为 null 时不注入订阅地址', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows());
      expect(yaml, isNot(contains('sub-url:')));
    });

    test('subUrl 为空串时不注入订阅地址', () {
      final yaml = ConfigGenerator.generateClashConfig(_makeRows(), subUrl: '');
      expect(yaml, isNot(contains('sub-url:')));
    });

    test('空节点列表仍然生成完整结构', () {
      final yaml = ConfigGenerator.generateClashConfig([]);
      expect(yaml, contains('port: 7890'));
      expect(yaml, contains('proxies:'));
      expect(yaml, contains('proxy-groups:'));
      expect(yaml, contains('rules:'));
      expect(yaml, contains('MATCH,🐟 漏网之鱼'));
    });

    test('SS 节点在 proxies 中类型正确', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final yaml = ConfigGenerator.generateClashConfig(rows);
      expect(yaml, contains('type: ss'));
      expect(yaml, contains('cipher: auto'));
      expect(yaml, contains('password: placeholder'));
    });

    test('VMess 节点在 proxies 中包含 uuid', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final yaml = ConfigGenerator.generateClashConfig(rows);
      expect(yaml, contains('type: vmess'));
      expect(yaml, contains('uuid: 00000000-0000-0000-0000-000000000000'));
    });

    test('Trojan 节点在 proxies 中包含 password', () {
      final rows = [ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms')];
      final yaml = ConfigGenerator.generateClashConfig(rows);
      expect(yaml, contains('type: trojan'));
      expect(yaml, contains('password: placeholder'));
    });

    test('无效节点被跳过不出现在 proxies 中', () {
      final rows = [
        ResultRow('invalid_node', '50.00 ms'),
        ResultRow('1.2.3.4:443#US', '50.00 ms'),
      ];
      final yaml = ConfigGenerator.generateClashConfig(rows);
      // 只有 1 个有效节点出现
      final proxyCount = 'server:'.allMatches(yaml).length;
      expect(proxyCount, 1);
    });
  });

  // =========================================================================
  // generateSingboxConfig
  // =========================================================================

  group('generateSingboxConfig', () {
    test('输出是合法 JSON', () {
      final json = ConfigGenerator.generateSingboxConfig(_makeRows());
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('包含 log 段', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      expect(config['log'], isNotNull);
      expect(config['log']['level'], 'info');
      expect(config['log']['timestamp'], true);
    });

    test('包含 mixed 入站在端口 7890', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      final inbounds = config['inbounds'] as List;
      expect(inbounds.length, 1);
      final inbound = inbounds.first as Map<String, dynamic>;
      expect(inbound['type'], 'mixed');
      expect(inbound['listen_port'], 7890);
      expect(inbound['listen'], '127.0.0.1');
    });

    test('outbounds 包含选择组、urltest 组、节点出站、direct 和 block', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      // 选择组 + urltest 组 + 3 个节点 + direct + block = 7
      expect(outbounds.length, 7);

      final tags = outbounds.map((o) => o['tag']).toList();
      expect(tags, contains('🚀 节点选择'));
      expect(tags, contains('♻️ 自动选择'));
      expect(tags, contains('direct'));
      expect(tags, contains('block'));
    });

    test('selector 出站的 outbounds 引用正确', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final selector = outbounds.firstWhere((o) => o['type'] == 'selector');
      final refs = selector['outbounds'] as List;
      expect(refs.first, '♻️ 自动选择');
      expect(refs.contains('direct'), true);
    });

    test('urltest 出站配置正确', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final urltest = outbounds.firstWhere((o) => o['type'] == 'urltest');
      expect(urltest['url'], 'http://www.gstatic.com/generate_204');
      expect(urltest['interval'], '300s');
      expect((urltest['outbounds'] as List).length, 3);
    });

    test('SS 节点类型为 shadowsocks', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final ss = outbounds.firstWhere((o) => o['tag'] != null && o['type'] == 'shadowsocks');
      expect(ss['server'], '1.2.3.4');
      expect(ss['server_port'], 443);
      expect(ss['method'], 'auto');
      expect(ss['password'], 'placeholder');
    });

    test('VMess 节点包含 uuid 和 transport', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final vmess = outbounds.firstWhere((o) => o['type'] == 'vmess');
      expect(vmess['uuid'], '00000000-0000-0000-0000-000000000000');
      expect(vmess['alter_id'], 0);
      expect(vmess['security'], 'auto');
      expect(vmess['transport']['type'], 'tcp');
    });

    test('Trojan 节点包含 transport', () {
      final rows = [ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms')];
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final trojan = outbounds.firstWhere((o) => o['type'] == 'trojan');
      expect(trojan['password'], 'placeholder');
      expect(trojan['transport']['type'], 'tcp');
    });

    test('route 包含基本规则', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig(_makeRows()))
          as Map<String, dynamic>;
      final route = config['route'] as Map<String, dynamic>;
      expect(route['final'], '🚀 节点选择');

      final rules = route['rules'] as List;
      expect(rules.length, 3);

      // .cn 直连
      final cnRule = rules.firstWhere((r) => r['domain_suffix'] != null);
      expect(cnRule['domain_suffix'], contains('.cn'));
      expect(cnRule['outbound'], 'direct');

      // google/github 走代理
      final kwRule = rules.firstWhere((r) => r['domain_keyword'] != null);
      expect(kwRule['domain_keyword'], containsAll(['google', 'github']));

      // 内网直连
      final ipRule = rules.firstWhere((r) => r['ip_cidr'] != null);
      expect(ipRule['outbound'], 'direct');
    });

    test('空节点列表仍然生成完整结构', () {
      final config = jsonDecode(ConfigGenerator.generateSingboxConfig([]))
          as Map<String, dynamic>;
      expect(config['log'], isNotNull);
      expect(config['inbounds'], isNotEmpty);
      expect(config['outbounds'], isNotEmpty);
      expect(config['route'], isNotNull);
      // 选择组 + urltest + direct + block = 4
      expect((config['outbounds'] as List).length, 4);
    });
  });

  // =========================================================================
  // generateV2rayConfig
  // =========================================================================

  group('generateV2rayConfig', () {
    test('输出是合法 JSON', () {
      final json = ConfigGenerator.generateV2rayConfig(_makeRows());
      expect(() => jsonDecode(json), returnsNormally);
    });

    test('包含 log 段', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      expect(config['log'], isNotNull);
      expect(config['log']['loglevel'], 'info');
    });

    test('inbounds 包含 socks 1080 和 http 1081', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      final inbounds = config['inbounds'] as List;
      expect(inbounds.length, 2);

      final socksIn = inbounds.firstWhere((i) => i['protocol'] == 'socks');
      expect(socksIn['port'], 1080);
      expect(socksIn['listen'], '127.0.0.1');
      expect(socksIn['settings']['udp'], true);

      final httpIn = inbounds.firstWhere((i) => i['protocol'] == 'http');
      expect(httpIn['port'], 1081);
      expect(httpIn['listen'], '127.0.0.1');
    });

    test('outbounds 包含多个 proxy 出站和 direct', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      // 2 个 proxy (proxy-0, proxy-1) + direct + block = 4
      expect(outbounds.length, greaterThanOrEqualTo(3));

      final tags = outbounds.map((o) => o['tag']).toList();
      expect(tags, contains('proxy-0'));
      expect(tags, contains('direct'));
    });

    test('proxy 出站使用对应节点的协议和地址', () {
      final rows = [ResultRow('1.2.3.4:443#US CM', '50.00 ms')];
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy-0');
      expect(proxy['protocol'], 'ss');
      final servers = proxy['settings']['servers'] as List;
      expect(servers.first['address'], '1.2.3.4');
      expect(servers.first['port'], 443);
    });

    test('direct 出站为 freedom 协议', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final direct = outbounds.firstWhere((o) => o['tag'] == 'direct');
      expect(direct['protocol'], 'freedom');
    });

    test('空节点列表时无 proxy 出站', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig([]))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final tags = outbounds.map((o) => o['tag']).toList();
      expect(tags, contains('direct'));
      expect(tags.where((t) => t.toString().startsWith('proxy-')), isEmpty);
    });

    test('routing 包含基本规则', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      final routing = config['routing'] as Map<String, dynamic>;
      expect(routing['domainStrategy'], 'IPIfNonMatch');

      final rules = routing['rules'] as List;
      expect(rules.length, 3);

      // cn 域名直连
      final cnRule = rules.firstWhere(
          (r) => (r['domain'] as List?)?.contains('domain:cn') == true);
      expect(cnRule['outboundTag'], 'direct');

      // google/github 走代理
      final kwRule = rules.firstWhere((r) {
        final domains = r['domain'] as List?;
        return domains != null &&
            domains.contains('geosite:google') &&
            domains.contains('geosite:github');
      });
      // 使用 balancer 负载均衡
      expect(kwRule['balancerTag'] ?? kwRule['outboundTag'], isNotNull);

      // 内网/CN 直连
      final ipRule = rules.firstWhere((r) {
        final ips = r['ip'] as List?;
        return ips != null && ips.contains('geoip:cn');
      });
      expect(ipRule['outboundTag'], 'direct');
    });

    test('streamSettings 使用 tcp', () {
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(_makeRows()))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy-0');
      expect(proxy['streamSettings']['network'], 'tcp');
    });

    test('VMess proxy 出站使用 vnext 格式', () {
      final rows = [ResultRow('10.0.0.1:8080#HK VMess', '120.50ms')];
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy-0');
      expect(proxy['protocol'], 'vmess');
      final vnext = proxy['settings']['vnext'] as List;
      expect(vnext.first['address'], '10.0.0.1');
      expect(vnext.first['port'], 8080);
    });

    test('Trojan proxy 出站使用 servers 格式', () {
      final rows = [ResultRow('[2001:db8::1]:443#JP Trojan', '30.00 ms')];
      final config = jsonDecode(ConfigGenerator.generateV2rayConfig(rows))
          as Map<String, dynamic>;
      final outbounds = config['outbounds'] as List;
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy-0');
      expect(proxy['protocol'], 'trojan');
      final servers = proxy['settings']['servers'] as List;
      expect(servers.first['address'], '2001:db8::1');
      expect(servers.first['port'], 443);
      expect(servers.first['password'], 'placeholder');
    });
  });
}
