import 'package:cfnb_app/core/error/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppFailure sealed class', () {
    group('NetworkFailure', () {
      test('基本构造', () {
        const f = NetworkFailure('连接超时');
        expect(f.message, '连接超时');
        expect(f.url, isEmpty);
        expect(f.statusCode, isNull);
        expect(f.cause, isNull);
      });

      test('带 URL 和状态码', () {
        const f = NetworkFailure('HTTP 错误', url: 'https://example.com', statusCode: 403);
        expect(f.toString(), contains('网络错误'));
        expect(f.toString(), contains('example.com'));
        expect(f.toString(), contains('403'));
      });

      test('无 URL 时省略括号', () {
        const f = NetworkFailure('DNS 解析失败');
        expect(f.toString(), '网络错误：DNS 解析失败');
      });
    });

    group('TlsFailure', () {
      test('toString 包含 TLS 错误前缀', () {
        const f = TlsFailure('证书过期');
        expect(f.toString(), 'TLS 错误：证书过期');
      });

      test('可携带 cause', () {
        final cause = Exception('inner');
        final f = TlsFailure('握手失败', cause);
        expect(f.cause, cause);
      });
    });

    group('IoFailure', () {
      test('带路径', () {
        const f = IoFailure('文件不存在', path: '/tmp/test.txt');
        expect(f.toString(), contains('/tmp/test.txt'));
        expect(f.toString(), contains('IO 错误'));
      });

      test('无路径时省略括号', () {
        const f = IoFailure('写入失败');
        expect(f.toString(), 'IO 错误：写入失败');
      });
    });

    group('ConfigFailure', () {
      test('toString 包含配置错误前缀', () {
        const f = ConfigFailure('Token 不能为空');
        expect(f.toString(), '配置错误：Token 不能为空');
      });
    });

    group('GitHubFailure', () {
      test('带状态码', () {
        const f = GitHubFailure('权限不足', statusCode: 403);
        expect(f.toString(), contains('GitHub 错误'));
        expect(f.toString(), contains('403'));
      });

      test('无状态码', () {
        const f = GitHubFailure('网络超时');
        expect(f.toString(), 'GitHub 错误：网络超时');
      });
    });

    group('CancelledFailure', () {
      test('默认消息', () {
        const f = CancelledFailure();
        expect(f.toString(), '操作已取消');
        expect(f.message, '操作已取消');
      });

      test('自定义消息', () {
        const f = CancelledFailure('用户中断');
        expect(f.toString(), '用户中断');
      });
    });

    group('sealed class 特性', () {
      test('所有子类型都是 AppFailure', () {
        const failures = <AppFailure>[
          NetworkFailure('net'),
          TlsFailure('tls'),
          IoFailure('io'),
          ConfigFailure('cfg'),
          GitHubFailure('gh'),
          CancelledFailure(),
        ];
        for (final f in failures) {
          expect(f, isA<AppFailure>());
          expect(f, isA<Exception>());
          expect(f.message, isNotEmpty);
        }
      });

      test('exhaustive pattern matching', () {
        String describe(AppFailure f) => switch (f) {
              NetworkFailure(:final url) => 'net:$url',
              TlsFailure() => 'tls',
              IoFailure(:final path) => 'io:$path',
              ConfigFailure() => 'cfg',
              GitHubFailure(:final statusCode) => 'gh:$statusCode',
              CancelledFailure() => 'cancelled',
            };

        expect(describe(const NetworkFailure('', url: 'u')), 'net:u');
        expect(describe(const TlsFailure('')), 'tls');
        expect(describe(const IoFailure('', path: 'p')), 'io:p');
        expect(describe(const ConfigFailure('')), 'cfg');
        expect(describe(const GitHubFailure('', statusCode: 200)), 'gh:200');
        expect(describe(const CancelledFailure()), 'cancelled');
      });
    });
  });
}
