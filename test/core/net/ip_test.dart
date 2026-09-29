import 'package:cfnb_app/core/net/ip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isIp IPv4', () {
    expect(isIp('1.2.3.4'), isTrue);
    expect(isIp('999.1.1.1'), isFalse);
    expect(isIp('1.2.3'), isFalse);
    expect(isIp('example.com'), isFalse);
  });
  test('isIp IPv6', () {
    expect(isIp('[::1]'), isTrue);
    expect(isIp('2001:db8::1'), isTrue);
    expect(isIp('::1'), isTrue);
    expect(isIp('example.com'), isFalse);
  });
  test('isCloudflareIp', () {
    expect(isCloudflareIp('104.16.0.1'), isTrue);
    expect(isCloudflareIp('104.31.255.255'), isTrue);
    expect(isCloudflareIp('162.158.0.1'), isTrue);
    expect(isCloudflareIp('162.159.255.255'), isTrue);
    expect(isCloudflareIp('172.64.0.1'), isTrue);
    expect(isCloudflareIp('172.71.255.255'), isTrue);
    expect(isCloudflareIp('108.162.192.1'), isTrue);
    expect(isCloudflareIp('8.8.8.8'), isFalse);
    expect(isCloudflareIp('1.1.1.1'), isFalse);
    expect(isCloudflareIp('192.168.1.1'), isFalse);
  });
  group('bracketIpv6Host', () {
    test('bare ipv6 with port gets brackets', () {
      expect(
        bracketIpv6Host('2606:4700:8394:b884:22e2:7cb7:25bd:b7da:443#US'),
        '[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#US',
      );
      expect(
        bracketIpv6Host('2606:4700:8394:b884:22e2:7cb7:25bd:b7da:443'),
        '[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443',
      );
    });
    test('bare ipv6 without port gets brackets', () {
      expect(bracketIpv6Host('2001:db8::1'), '[2001:db8::1]');
      expect(bracketIpv6Host('::1'), '[::1]');
      expect(bracketIpv6Host('fe80::1#US'), '[fe80::1]#US');
    });
    test('compressed ipv6 with port gets brackets', () {
      expect(bracketIpv6Host('2001:db8::1:443'), '[2001:db8::1]:443');
    });
    test('idempotent for already bracketed', () {
      expect(bracketIpv6Host('[2606:4700::1]:443#US'), '[2606:4700::1]:443#US');
    });
    test('leaves ipv4 and domain untouched', () {
      expect(bracketIpv6Host('1.2.3.4:443#US'), '1.2.3.4:443#US');
      expect(bracketIpv6Host('example.com:2053#US'), 'example.com:2053#US');
      expect(bracketIpv6Host('1.2.3.4'), '1.2.3.4');
    });
  });
  group('cfAirportToCountry', () {
    test('maps known airports', () {
      expect(cfAirportToCountry('hkg'), 'HK');
      expect(cfAirportToCountry('SIN'), 'SG');
      expect(cfAirportToCountry('NRT'), 'JP');
    });
    test('returns empty for unknown airport', () {
      expect(cfAirportToCountry('XXX'), '');
    });
  });

  group('parseEgressTrace', () {
    const full = 'ip=203.0.113.7\nts=1690000000.000\nvisit_scheme=https\n'
        'colo=LAX\nsliver=none\nhttp=HTTP/1.1\ngeo=US\n';

    test('解析出口 IP 与 colo', () {
      final e = parseEgressTrace(full);
      expect(e, isNotNull);
      expect(e!.ip, '203.0.113.7');
      expect(e.colo, 'LAX');
    });

    test('缺 colo 时仍返回出口 IP，colo 为空', () {
      final e = parseEgressTrace('ip=1.2.3.4\ngeo=JP\n');
      expect(e!.ip, '1.2.3.4');
      expect(e.colo, '');
    });

    test('IPv6 出口地址（含冒号）也能解析', () {
      expect(parseEgressTrace('ip=2606:4700::6812:3456\ncolo=FRA\n')!.ip,
          '2606:4700::6812:3456');
    });

    test('缺 ip= 或空文本返回 null', () {
      expect(parseEgressTrace('colo=LAX\ngeo=US\n'), isNull);
      expect(parseEgressTrace(''), isNull);
    });

    test('ip= 只在行首匹配，不误读其它字段', () {
      expect(parseEgressTrace('colo=LAX\nxip=9.9.9.9\n'), isNull);
    });
  });
}
