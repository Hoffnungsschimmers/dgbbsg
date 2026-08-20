import 'package:cfnb_app/core/net/retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('retry', () {
    test('success on first attempt does not sleep or retry', () async {
      final sleeps = <Duration>[];
      int calls = 0;
      final result = await retry<int>(
        () async {
          calls++;
          return 42;
        },
        maxRetries: 3,
        initialDelay: const Duration(seconds: 1),
        sleep: (d) async {
          sleeps.add(d);
        },
      );
      expect(result, 42);
      expect(calls, 1);
      expect(sleeps, isEmpty);
    });

    test('retries until success within maxRetries', () async {
      final sleeps = <Duration>[];
      int calls = 0;
      final result = await retry<int>(
        () async {
          calls++;
          if (calls < 3) throw StateError('fail #$calls');
          return 7;
        },
        maxRetries: 3,
        initialDelay: const Duration(seconds: 1),
        sleep: (d) async {
          sleeps.add(d);
        },
      );
      expect(result, 7);
      expect(calls, 3);
      expect(sleeps, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    });

    test('maxRetries=0 means no retry', () async {
      final sleeps = <Duration>[];
      int calls = 0;
      await expectLater(
        retry<int>(
          () async {
            calls++;
            throw StateError('always fails');
          },
          maxRetries: 0,
          initialDelay: const Duration(seconds: 1),
          sleep: (d) async {
            sleeps.add(d);
          },
        ),
        throwsStateError,
      );
      expect(calls, 1);
      expect(sleeps, isEmpty);
    });

    test('exponential backoff sequence sleeps initial*2^attempt', () async {
      final sleeps = <Duration>[];
      int calls = 0;
      await expectLater(
        retry<int>(
          () async {
            calls++;
            throw StateError('boom');
          },
          maxRetries: 5,
          initialDelay: const Duration(milliseconds: 100),
          sleep: (d) async {
            sleeps.add(d);
          },
        ),
        throwsStateError,
      );
      expect(calls, 6);
      expect(sleeps, [
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 800),
        const Duration(milliseconds: 1600),
      ]);
    });
  });
}
