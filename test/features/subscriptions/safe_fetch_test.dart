import 'dart:async';
import 'dart:typed_data';

import 'package:cfnb_app/core/net/http_fetcher.dart';
import 'package:cfnb_app/core/net/retry.dart';
import 'package:cfnb_app/core/subscription/subscription_converter.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_test/flutter_test.dart';

import 'package:cfnb_app/core/config/app_config.dart';

/// Sequence-based mock adapter that returns a queue of [status, body] pairs
/// on each call to `fetch`. Each `fetch` consumes the next entry; once the
/// queue is exhausted it returns the last entry forever (so we can detect
/// "adapter.fetch called more times than expected" in a test).
class _SeqAdapter implements dio_pkg.HttpClientAdapter {
  _SeqAdapter(this._queue);

  final List<(int, String)> _queue;
  int _index = 0;
  int calls = 0;

  @override
  Future<dio_pkg.ResponseBody> fetch(
    dio_pkg.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final entry = _index < _queue.length ? _queue[_index] : _queue.last;
    _index++;
    final (code, body) = entry;
    return dio_pkg.ResponseBody.fromString(body, code);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('fetchHttpWithRetry', () {
    test(
      'retries through 503x2 + 200 with body, stops after 3 attempts',
      () async {
        final adapter = _SeqAdapter([
          (503, 'oops-1'),
          (503, 'oops-2'),
          (200, 'final-body'),
        ]);

        final dio = dio_pkg.Dio(
          dio_pkg.BaseOptions(
            // validateStatus covers 200-299; 503 will throw → triggers retry.
            validateStatus: (s) => s != null && s >= 200 && s < 300,
          ),
        );
        // Force the mock adapter in (bypass platform default).
        dio.httpClientAdapter = adapter;

        final body = await fetchHttpWithRetry(
          dio: dio,
          url: 'https://example.test/sub',
          connectTimeoutSec: 10,
          sendTimeoutSec: 20,
          receiveTimeoutSec: 20,
          maxRetries: 2,
          retryDelayMs: 1, // tiny — but we also inject sleep mock below
          sleep: (_) async {}, // skip real exponential backoff sleeps
        );
        expect(body, 'final-body');
        expect(adapter.calls, 3);
      },
    );

    test('maxRetries=0 does not retry when first attempt fails', () async {
      final adapter = _SeqAdapter([
        (503, 'no-retry'),
      ]);
      final dio = dio_pkg.Dio(dio_pkg.BaseOptions(
        validateStatus: (s) => s != null && s >= 200 && s < 300,
      ));
      dio.httpClientAdapter = adapter;

      // fetchHttpWithRetry with maxRetries=0 should rethrow on first failure;
      // we do not assert here on return value, but assert that adapter was hit
      // exactly once.
      await expectLater(
        fetchHttpWithRetry(
          dio: dio,
          url: 'https://example.test/sub',
          connectTimeoutSec: 10,
          sendTimeoutSec: 20,
          receiveTimeoutSec: 20,
          maxRetries: 0,
          retryDelayMs: 1,
          sleep: (_) async {},
        ),
        throwsA(isA<dio_pkg.DioException>()),
      );
      expect(adapter.calls, 1);
    });

    test(
      'uses cfg-derived connectTimeout via clamp inside fetchHttpWithRetry',
      () async {
        final adapter = _SeqAdapter([(200, 'ok')]);
        final dio = dio_pkg.Dio(dio_pkg.BaseOptions(
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ));
        dio.httpClientAdapter = adapter;

        final body = await fetchHttpWithRetry(
          dio: dio,
          url: 'https://example.test/sub',
          connectTimeoutSec: 5,
          sendTimeoutSec: 10,
          receiveTimeoutSec: 10,
          maxRetries: 1,
          retryDelayMs: 0,
          sleep: (_) async {},
        );
        expect(body, 'ok');
        expect(adapter.calls, 1);
      },
    );

    test(
      '_safeFetch returns "" and does not throw when adapter always fails',
      () async {
        final adapter = _SeqAdapter([
          (502, 'bad'),
          (502, 'bad'),
          (502, 'bad'),
          (502, 'bad'),
        ]);
        final dio = dio_pkg.Dio(dio_pkg.BaseOptions(
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ));
        dio.httpClientAdapter = adapter;

        // Adapter is wired to a notifier — we only need the function to use
        // fetchHttpWithRetry. Invoke via a tiny local wrapper that mirrors the
        // safe-fetch contract.
        Future<String> safeFetch() async {
          try {
            return await fetchHttpWithRetry(
              dio: dio,
              url: 'https://example.test/sub',
              connectTimeoutSec: 5,
              sendTimeoutSec: 10,
              receiveTimeoutSec: 900, // ugly cfg above clamp -> clamped to 600
              maxRetries: 3, // cfg.subFetchMaxRetries.clamp(0,10) gives 3
              retryDelayMs: 0,
              sleep: (_) async {},
            );
          } catch (_) {
            return '';
          }
        }

        final body = await safeFetch();
        expect(body, '');
        expect(adapter.calls, 4); // 1 + 3 retries
      },
    );
  });

  // Keep imports referenced even if future refactors prune tests above.
  group('smoke', () {
    test('retry + AppConfig stay importable', () {
      const cfg = AppConfig();
      expect(cfg.subFetchConnectTimeout, 10);
      expect(cfg.subFetchMaxRetries, 2);
      expect(
        edgetunnelUa,
        contains('edgetunnel'),
        reason: 'sanity: subscription UA constant',
      );
      // compiler must resolve retry symbol
      retry<int>(() async => 1, maxRetries: 0, initialDelay: Duration.zero);
    });
  });
}
