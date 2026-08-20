import 'dart:convert';

import 'package:dio/dio.dart';

/// 404 专用异常：请求的文件在云盘上不存在（区别于网络/服务器错误）。
class WebDavNotFoundException implements Exception {
  final String path;
  WebDavNotFoundException(this.path);

  @override
  String toString() => 'WebDavNotFoundException: $path';
}

/// 极简 WebDAV 客户端：仅需 PUT（上传）与 GET（下载）两个操作，
/// 面向坚果云/群晖/Nextcloud 等通用 WebDAV 云盘，用于配置与结果文件的备份/恢复。
class WebDavClient {
  final Dio _dio;
  final String baseUrl;
  final String user;

  WebDavClient({
    required this.baseUrl,
    required this.user,
    required String password,
    int connectTimeoutMs = 15000,
    int sendTimeoutMs = 60000,
    int receiveTimeoutMs = 60000,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    _dio.options
      ..connectTimeout = Duration(milliseconds: connectTimeoutMs)
      ..sendTimeout = Duration(milliseconds: sendTimeoutMs)
      ..receiveTimeout = Duration(milliseconds: receiveTimeoutMs)
      ..headers['Authorization'] = auth;
  }

  /// 上传文件内容到 [path]（相对 baseUrl，如 `backup/cfnb_config.json`）。
  Future<void> upload(String path, List<int> bytes) async {
    final resp = await _dio.put<dynamic>(
      _url(path),
      data: Stream.fromIterable([bytes]),
      options: Options(headers: {'Content-Type': 'application/octet-stream'}),
    );
    if (resp.statusCode == null || resp.statusCode! >= 400) {
      throw Exception('WebDAV 上传失败（HTTP ${resp.statusCode}）');
    }
  }

  /// 下载 [path] 的内容。文件不存在（404）时抛 [WebDavNotFoundException]。
  Future<List<int>> download(String path) async {
    try {
      final resp = await _dio.get<dynamic>(
        _url(path),
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.statusCode == null || resp.statusCode! >= 400) {
        throw Exception('WebDAV 下载失败（HTTP ${resp.statusCode}）');
      }
      return (resp.data as List<int>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw WebDavNotFoundException(path);
      }
      rethrow;
    }
  }

  String _url(String path) {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final p = path.replaceAll(RegExp(r'^/+'), '');
    return '$base/$p';
  }
}