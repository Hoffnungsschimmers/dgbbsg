import 'package:cfnb_app/core/notification/webhook_sender.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebhookSender', () {
    late WebhookSender sender;

    setUp(() {
      sender = WebhookSender(Dio());
    });

    group('send', () {
      test('returns false for type=none', () async {
        final ok = await sender.send(
          type: 'none',
          url: 'https://example.com',
          title: 'T',
          body: 'B',
        );
        expect(ok, isFalse);
      });

      test('returns false for empty url', () async {
        final ok = await sender.send(
          type: 'telegram',
          url: '',
          title: 'T',
          body: 'B',
        );
        expect(ok, isFalse);
      });

      test('returns false for unknown type', () async {
        final ok = await sender.send(
          type: 'slack',
          url: 'https://example.com',
          title: 'T',
          body: 'B',
        );
        expect(ok, isFalse);
      });

      test('returns false for invalid telegram url (network error)', () async {
        final ok = await sender.send(
          type: 'telegram',
          url: 'https://localhost:1/nonexistent',
          title: 'Test',
          body: 'Body',
        );
        expect(ok, isFalse);
      });

      test('returns false for invalid discord url (network error)', () async {
        final ok = await sender.send(
          type: 'discord',
          url: 'https://localhost:1/nonexistent',
          title: 'Test',
          body: 'Body',
        );
        expect(ok, isFalse);
      });
    });

    group('sendTelegram', () {
      test('returns false on network error', () async {
        final ok = await sender.sendTelegram(
          'https://localhost:1/bot:test/sendMessage',
          'hello',
        );
        expect(ok, isFalse);
      });
    });

    group('sendDiscord', () {
      test('returns false on network error', () async {
        final ok = await sender.sendDiscord(
          'https://localhost:1/webhooks/test',
          'hello',
        );
        expect(ok, isFalse);
      });
    });
  });
}
