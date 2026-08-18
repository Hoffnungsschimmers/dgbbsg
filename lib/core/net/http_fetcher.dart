import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;

import '../subscription/subscription_converter.dart' show edgetunnelUa;
import 'retry.dart';

/// 走 Dio 带 cfg 化超时与指数退避重试的 HTTP GET，返回 body 明文。
///
/// 成功响应 (status 200-299) 直接返回 `.data.toString()`；其它状态码被 Dio
/// 默认的 `validateStatus` 判定并转换成 [dio_pkg.DioException]，由
/// [retry] 捕获并触发下一次尝试。
///
/// - 三档超时 (`connectTimeout`/`sendTimeout`/`receiveTimeout`) 与 `maxRetries`
///   由调用方从 [AppConfig] 注入；本函数只在内部做 `clamp` 防御非法值。
/// - `sleep` 默认为 [Future.delayed]；测试可注入 mock 以跳过真实指数退避。
/// - `maxRetries` 语义：`0` 表示不重试（只走第一次），与 [retry] 一致。
Future<String> fetchHttpWithRetry({
  required dio_pkg.Dio dio,
  required String url,
  required int connectTimeoutSec,
  required int sendTimeoutSec,
  required int receiveTimeoutSec,
  required int maxRetries,
  required int retryDelayMs,
  Future<void> Function(Duration)? sleep,
  void Function(String)? onLog,
}) async {
  Future<String> doGet() async {
    final resp = await dio.get<String>(
      url,
      options: dio_pkg.Options(
        responseType: dio_pkg.ResponseType.plain,
        headers: const {
          'User-Agent': edgetunnelUa,
          'Accept': '*/*',
        },
        connectTimeout: Duration(seconds: connectTimeoutSec.clamp(1, 300)),
        sendTimeout: Duration(seconds: sendTimeoutSec.clamp(1, 600)),
        receiveTimeout: Duration(seconds: receiveTimeoutSec.clamp(1, 600)),
      ),
    );
    return resp.data.toString();
  }

  final retries = maxRetries.clamp(0, 10);
  return retry<String>(
    doGet,
    maxRetries: retries,
    initialDelay: Duration(milliseconds: retryDelayMs),
    sleep: sleep,
    onRetry: retries > 0
        ? (attempt, max, error, delay) {
            onLog?.call('  ↻ 重试 $attempt/$max（${classifyFetchError(error, url)}，'
                '${(delay.inMilliseconds / 1000).toStringAsFixed(1)}s 后重试）');
          }
        : null,
  );
}

/// 把抓取异常分类为可读提示（供日志/排障）。纯函数。
String classifyFetchError(Object e, String url) {
  if (e is dio_pkg.DioException) {
    final t = e.type;
    if (t == dio_pkg.DioExceptionType.connectionTimeout ||
        t == dio_pkg.DioExceptionType.sendTimeout) {
      return '连接超时（源不可达或被墙）';
    }
    if (t == dio_pkg.DioExceptionType.receiveTimeout) {
      return '读取超时（响应过慢）';
    }
    if (t == dio_pkg.DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      final hint = (code == 403 && url.contains('/sub'))
          ? '（该 edgetunnel 部署可能未启用 BEST_SUB：请在 Cloudflare 变量设置 BEST_SUB=1）'
          : '';
      return 'HTTP ${code ?? '?'} 错误$hint';
    }
    if (t == dio_pkg.DioExceptionType.connectionError) {
      return '连接失败（DNS/网络不可达）';
    }
    // 检查底层异常：TLS 握手失败 / 证书错误
    final inner = e.error;
    if (inner is HandshakeException) {
      final msg = inner.message;
      if (msg.contains('CERTIFICATE_VERIFY_FAILED')) {
        return 'TLS 证书校验失败（域名与证书不匹配或证书不受信，可尝试开启「跳过 TLS 证书校验」）';
      }
      if (msg.contains('HANDSHAKE_FAILURE') || msg.contains('SSLV3_ALERT')) {
        return 'TLS 握手失败（服务端不兼容当前 TLS 版本/密码套件）';
      }
      return 'TLS 握手异常：$msg';
    }
    if (inner is SocketException) {
      return '网络连接失败：${inner.message}';
    }
    return '请求异常：${e.message ?? e}';
  }
  return '未知错误：$e';
}
