import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../net/proxy.dart';

/// GitHub 文件推送（对应旧版 scripts/git_sync.ps1 的 ip 数据推送）。
///
/// 推送到独立的 cf-ip 仓库（与代码仓库隔离）。使用 GitHub Contents API，
/// 自动处理已存在文件的 sha（更新）或新建。token 通过参数传入，不落盘明文。
class GithubPush {
  final String token;
  final String repo; // 形如 "owner/cf-ip"
  final String branch;
  final Dio dio;

  /// 可选：自定义请求发送器，便于测试注入假网络层。
  final Future<Response<dynamic>> Function(RequestOptions)? sender;

  /// 共享直连 Dio：自动读取 Windows 系统代理（注册表），适用于订阅抓取等
  /// 需经本地代理可达源的请求。Dart 的 HttpClient 不读 Windows 注册表代理，
  /// 必须手动配置 findProxy。
  /// [insecure] 为 true 时跳过 TLS 证书校验（对应 AppConfig.subInsecure），
  /// 默认 false 保持证书校验，代理 MITM 场景由用户显式开启。
  static Dio directDio({bool insecure = false}) {
    final dio = Dio(BaseOptions(
      headers: {'User-Agent': 'cfnb-app'},
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ));
    _applySystemProxy(dio, insecure: insecure);
    return dio;
  }

  /// 读取 Windows 系统代理并应用到 Dio 的 IO 适配器。
  /// 仅当 [insecure] 为 true 时跳过证书校验（如 Clash/V2RayN 使用自签证书
  /// 做 MITM 的代理环境）；默认保持 TLS 证书校验。
  /// GitHub API 走 DIRECT 直连（见构造函数），不受此影响。
  static void _applySystemProxy(Dio dio, {bool insecure = false}) {
    final proxy = readSystemProxy();
    if (proxy == null) return;
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY $proxy';
        if (insecure) {
          client.badCertificateCallback = (_, _, _) => true;
        }
        return client;
      };
    }
  }

  /// 仅允许推送优选结果文件（文件名以 _top.txt 结尾，如 addressesapi_top.txt），其余文件不推送。
  static bool isPushable(String file) =>
      file.toLowerCase().endsWith('_top.txt');

  GithubPush({
    required this.token,
    required this.repo,
    this.branch = 'main',
    Dio? dio,
    this.sender,
  }) : dio = dio ??
        Dio(BaseOptions(
          baseUrl: 'https://api.github.com',
          validateStatus: (code) => code != null && (code >= 200 && code < 500),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'cfnb-app',
          },
        )) {
    // GitHub API 走直连，绕开本地代理（如 127.0.0.1:7890 的 Clash）——
    // 经代理访问 api.github.com 会被阻断/丢弃（实测 HTTP 000），直连则正常。
    final adapter = this.dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.userAgent = 'cfnb-app';
        return client;
      };
    }
  }

  /// 构造单次请求：把 Token / UA 显式带到 RequestOptions，避免某些 Dio 版本
  /// 在 `fetch()` 时不继承 BaseOptions.headers 导致 401。
  RequestOptions _req(String method, String path, {Map<String, dynamic>? data}) {
    final headers = <String, dynamic>{
      'Authorization': 'Bearer ${token.trim()}',
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'cfnb-app',
    };
    return RequestOptions(
      method: method,
      path: path,
      baseUrl: dio.options.baseUrl,
      headers: headers,
      data: data,
      validateStatus: dio.options.validateStatus,
      connectTimeout: dio.options.connectTimeout,
      receiveTimeout: dio.options.receiveTimeout,
    );
  }

  Future<Response<dynamic>> _send(RequestOptions options) => sender != null
      ? sender!(options)
      : dio.fetch(options);

  /// 构造 PUT body（提取已有 sha 用于更新，或仅新建）。
  static Map<String, dynamic> buildPutBody({
    required String path,
    required String content,
    required String branch,
    String? message,
    String? sha,
  }) =>
      {
        'message': message ?? 'update $path',
        'content': base64Encode(utf8.encode(content)),
        'branch': branch,
        if (sha != null) 'sha': sha,
      };

  /// 推送单个文件内容到仓库，返回 HTTP 状态码。
  /// [path] 可以是绝对路径（如 `C:/Users/.../addressesapi_top.txt`）或纯文件名；
  /// GitHub API 路径自动提取文件名部分。
  ///
  /// 当 [maxRetries] > 0 时，遇到 422 SHA 冲突会自动重新拉取 SHA 并重试
  /// （最多 [maxRetries] 次），实现无感知冲突解决。
  Future<int> pushFile(String path, String content, {String? message, int maxRetries = 2}) async {
    // Token 有效性自检：401 立即给出明确提示，避免看 GitHub 原始报错。
    try {
      final who = await _send(_req('GET', '/user'));
      if (who.statusCode == 401) {
        throw Exception(
            'GitHub Token 无效（GitHub 返回 401）。请：① 在 GitHub 网页重新生成 Classic token 并只勾 repo；② 复制时先清空再整段粘贴 \$token，避免带入空格/换行/全角空格');
      }
    } on DioException {
      // /user 异常也按无效处理，由下方 PUT 给出最终错误
    }

    // 从绝对路径提取纯文件名用于 GitHub API（如 C:/x/y/top.txt → top.txt）
    final fileName = path.contains('/') || path.contains('\\')
        ? path.split(RegExp(r'[/\\]')).last
        : path;
    final url = '/repos/$repo/contents/$fileName';

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      String? sha;
      try {
        final existing = await _send(_req('GET', url));
        final code = existing.statusCode ?? 0;
        if (code == 404) {
          // 文件不存在，新建
        } else if (code >= 200 && code < 300) {
          sha = (existing.data is Map ? existing.data['sha'] as String? : null);
        } else {
          throw Exception('GitHub GET $url 返回 HTTP $code，无法判断文件是否存在');
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // 文件不存在，新建
        } else {
          throw Exception('GitHub GET $url 网络异常：${e.message ?? e}');
        }
      }

      final body = buildPutBody(
        path: fileName,
        content: content,
        branch: branch,
        message: message,
        sha: sha,
      );
      final resp = await _send(_req('PUT', url, data: body));
      final code = resp.statusCode ?? 0;
      if (code == 401) {
        throw Exception(
            'GitHub 401：Token 无效或无该仓库访问权。请检查：① Token 是否完整无空格/换行；② Repo 是否拼写为「owner/仓名」且 Token 有 repo 权限；③ 该仓确实存在');
      }
      if (code == 422 && attempt < maxRetries) {
        // SHA 冲突：远程文件被他人修改，自动重新拉取 SHA 重试
        continue;
      }
      if (code == 422) {
        throw Exception('GitHub 422：文件 SHA 不匹配（已重试 $maxRetries 次），远程文件可能被频繁修改');
      }
      if (code < 200 || code >= 300) {
        final msg = resp.data is Map ? (resp.data['message'] ?? '') : '';
        throw Exception('GitHub PUT 失败：HTTP $code $msg');
      }
      return code;
    }
    throw Exception('GitHub 推送失败：重试耗尽');
  }

  /// 从 GitHub 拉取文件内容，返回 (content, sha)。
  /// 文件不存在时返回 (null, null)。sha 用于后续更新时传给 PUT API。
  Future<(String? content, String? sha)> pullFile(String path) async {
    final fileName = path.contains('/') || path.contains('\\')
        ? path.split(RegExp(r'[/\\]')).last
        : path;
    final url = '/repos/$repo/contents/$fileName';
    try {
      final resp = await _send(_req('GET', url));
      final code = resp.statusCode ?? 0;
      if (code == 404) return (null, null);
      if (code < 200 || code >= 300) {
        throw Exception('GitHub GET $url 返回 HTTP $code');
      }
      final data = resp.data;
      if (data is! Map) return (null, null);
      final sha = data['sha'] as String?;
      final encoded = data['content'] as String?;
      if (encoded == null) return (null, sha);
      final content = utf8.decode(base64Decode(encoded.replaceAll('\n', '')));
      return (content, sha);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return (null, null);
      throw Exception('GitHub GET $url 网络异常：${e.message ?? e}');
    }
  }

  /// 批量推送多个文件，返回 路径 -> HTTP 状态码 的映射。
  Future<Map<String, int>> pushMultiple(Map<String, String> files, {String? message}) async {
    final results = <String, int>{};
    for (final entry in files.entries) {
      results[entry.key] = await pushFile(entry.key, entry.value, message: message);
    }
    return results;
  }
}
