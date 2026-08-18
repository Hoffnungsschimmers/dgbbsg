/// 统一的应用级错误类型，替代散落各处的 try-catch + 字符串日志。
///
/// 使用 sealed class 使调用方必须处理每种情况（exhaustive matching）。
sealed class AppFailure implements Exception {
  final String message;
  final Object? cause;
  const AppFailure(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// 网络请求失败（超时、DNS、连接拒绝等）。
class NetworkFailure extends AppFailure {
  final String url;
  final int? statusCode;
  const NetworkFailure(String message, {this.url = '', this.statusCode, Object? cause})
      : super(message, cause);

  @override
  String toString() {
    final buf = StringBuffer('网络错误：$message');
    if (url.isNotEmpty) buf.write('（$url）');
    if (statusCode != null) buf.write(' [HTTP $statusCode]');
    return buf.toString();
  }
}

/// TLS / 证书相关错误。
class TlsFailure extends AppFailure {
  const TlsFailure(super.message, [super.cause]);

  @override
  String toString() => 'TLS 错误：$message';
}

/// 文件 I/O 错误。
class IoFailure extends AppFailure {
  final String path;
  const IoFailure(String message, {this.path = '', Object? cause})
      : super(message, cause);

  @override
  String toString() => path.isNotEmpty ? 'IO 错误（$path）：$message' : 'IO 错误：$message';
}

/// 配置验证错误。
class ConfigFailure extends AppFailure {
  const ConfigFailure(super.message, [super.cause]);

  @override
  String toString() => '配置错误：$message';
}

/// GitHub API 错误。
class GitHubFailure extends AppFailure {
  final int? statusCode;
  const GitHubFailure(String message, {this.statusCode, Object? cause})
      : super(message, cause);

  @override
  String toString() {
    final buf = StringBuffer('GitHub 错误：$message');
    if (statusCode != null) buf.write(' [HTTP $statusCode]');
    return buf.toString();
  }
}

/// 取消操作。
class CancelledFailure extends AppFailure {
  const CancelledFailure([super.message = '操作已取消']);

  @override
  String toString() => message;
}
