import 'package:cfnb_app/core/net/proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readSystemProxy', () {
    test('does not throw on any platform', () {
      // Should return String? without throwing regardless of the host OS.
      expect(() => readSystemProxy(), returnsNormally);
    });
  });

  group('parseProxyEnvValue', () {
    test('returns null for null input', () {
      expect(parseProxyEnvValue(null), isNull);
    });

    test('returns null for empty string', () {
      expect(parseProxyEnvValue(''), isNull);
    });

    test('strips http:// scheme', () {
      expect(parseProxyEnvValue('http://127.0.0.1:8080'), '127.0.0.1:8080');
    });

    test('strips https:// scheme', () {
      expect(parseProxyEnvValue('https://10.0.0.1:3128'), '10.0.0.1:3128');
    });

    test('strips socks5:// scheme', () {
      expect(parseProxyEnvValue('socks5://127.0.0.1:1080'), '127.0.0.1:1080');
    });

    test('handles bare host:port', () {
      expect(parseProxyEnvValue('192.168.1.1:8888'), '192.168.1.1:8888');
    });

    test('strips trailing slash', () {
      expect(
        parseProxyEnvValue('http://proxy.example.com:8080/'),
        'proxy.example.com:8080',
      );
    });

    test('strips multiple trailing slashes', () {
      expect(
        parseProxyEnvValue('http://proxy.example.com:8080///'),
        'proxy.example.com:8080',
      );
    });

    test('trims whitespace', () {
      expect(
        parseProxyEnvValue('  http://127.0.0.1:9090  '),
        '127.0.0.1:9090',
      );
    });

    test('returns null for whitespace-only string', () {
      expect(parseProxyEnvValue('   '), isNull);
    });
  });

  group('parseMacOsNetworksetupOutput', () {
    test('parses enabled proxy with port', () {
      const output = '''
Enabled: Yes
Server: 127.0.0.1
Port: 1080
Authenticated Proxy Enabled: 0
''';
      expect(parseMacOsNetworksetupOutput(output), '127.0.0.1:1080');
    });

    test('returns null when disabled', () {
      const output = '''
Enabled: No
Server:
Port: 0
Authenticated Proxy Enabled: 0
''';
      expect(parseMacOsNetworksetupOutput(output), isNull);
    });

    test('returns null when server is empty', () {
      const output = '''
Enabled: Yes
Server:
Port: 8080
''';
      expect(parseMacOsNetworksetupOutput(output), isNull);
    });

    test('uses default port 8080 when port line is missing', () {
      const output = '''
Enabled: Yes
Server: proxy.local
''';
      expect(parseMacOsNetworksetupOutput(output), 'proxy.local:8080');
    });

    test('handles case-insensitive "Yes"', () {
      const output = '''
Enabled: yes
Server: 10.0.0.1
Port: 3128
''';
      expect(parseMacOsNetworksetupOutput(output), '10.0.0.1:3128');
    });

    test('trims surrounding whitespace from values', () {
      const output = '''
Enabled:  Yes
Server:  my-proxy.example.com
Port:  8888
''';
      expect(
        parseMacOsNetworksetupOutput(output),
        'my-proxy.example.com:8888',
      );
    });
  });
}
