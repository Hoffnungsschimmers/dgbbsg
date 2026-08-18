import 'package:dio/dio.dart';

/// Webhook 通知发送器（Telegram Bot / Discord Webhook）。
///
/// 所有方法捕获异常并返回 false，绝不向调用方抛出异常。
class WebhookSender {
  final Dio _dio;

  WebhookSender(this._dio);

  /// 发送 Telegram Bot 消息。
  ///
  /// [url] 格式：`https://api.telegram.org/bot<token>/sendMessage?chat_id=<id>`
  /// 发送失败返回 false。
  Future<bool> sendTelegram(String url, String message) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        url,
        data: {'text': message, 'parse_mode': 'HTML'},
        options: Options(contentType: Headers.jsonContentType),
      );
      return resp.statusCode != null &&
          resp.statusCode! >= 200 &&
          resp.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  /// 发送 Discord Webhook 消息。
  ///
  /// [url] 格式：`https://discord.com/api/webhooks/<id>/<token>`
  /// 发送失败返回 false。
  Future<bool> sendDiscord(String url, String message) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        url,
        data: {'content': message},
        options: Options(contentType: Headers.jsonContentType),
      );
      return resp.statusCode != null &&
          resp.statusCode! >= 200 &&
          resp.statusCode! < 300;
    } catch (_) {
      return false;
    }
  }

  /// 统一发送入口。根据 [type] 分派到对应平台。
  ///
  /// - `title` 作为消息前缀（加粗显示）。
  /// - `body` 为正文内容。
  /// 返回是否发送成功。
  Future<bool> send({
    required String type,
    required String url,
    required String title,
    required String body,
  }) async {
    if (type == 'none' || url.isEmpty) return false;
    switch (type) {
      case 'telegram':
        return sendTelegram(url, '<b>$title</b>\n$body');
      case 'discord':
        return sendDiscord(url, '**$title**\n$body');
      default:
        return false;
    }
  }
}
