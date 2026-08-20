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
}
