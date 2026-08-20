import 'package:cfnb_app/core/net/http_fetcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyFetchError', () {
    test('connectionTimeout returns timeout message', () {
      final e = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: ''),
      );
      expect(classifyFetchError(e, 'https://example.com'), contains('连接超时'));
    });

    test('sendTimeout returns timeout message', () {
      final e = DioException(
        type: DioExceptionType.sendTimeout,
        requestOptions: RequestOptions(path: ''),
      );
      expect(classifyFetchError(e, 'https://example.com'), contains('连接超时'));
    });

    test('receiveTimeout returns read timeout message', () {
      final e = DioException(
        type: DioExceptionType.receiveTimeout,
        requestOptions: RequestOptions(path: ''),
      );
      expect(classifyFetchError(e, 'https://example.com'), contains('读取超时'));
    });

    test('badResponse returns HTTP error code', () {
      final e = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 403,
          requestOptions: RequestOptions(path: ''),
        ),
      );
      final msg = classifyFetchError(e, 'https://example.com/sub');
      expect(msg, contains('HTTP 403'));
    });

    test('badResponse with /sub url and 403 includes BEST_SUB hint', () {
      final e = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 403,
          requestOptions: RequestOptions(path: ''),
        ),
      );
      final msg = classifyFetchError(e, 'https://example.com/sub');
      expect(msg, contains('BEST_SUB'));
    });

    test('badResponse with /sub url and 500 does not include BEST_SUB hint', () {
      final e = DioException(
        type: DioExceptionType.badResponse,
        requestOptions: RequestOptions(path: ''),
        response: Response(
          statusCode: 500,
          requestOptions: RequestOptions(path: ''),
        ),
      );
      final msg = classifyFetchError(e, 'https://example.com/sub');
      expect(msg, contains('HTTP 500'));
      expect(msg, isNot(contains('BEST_SUB')));
    });

    test('connectionError returns DNS/network message', () {
      final e = DioException(
        type: DioExceptionType.connectionError,
        requestOptions: RequestOptions(path: ''),
      );
      expect(classifyFetchError(e, 'https://example.com'), contains('连接失败'));
    });

    test('unknown non-Dio error returns unknown message', () {
      final msg = classifyFetchError(Exception('boom'), 'https://example.com');
      expect(msg, contains('未知错误'));
    });
  });
}
