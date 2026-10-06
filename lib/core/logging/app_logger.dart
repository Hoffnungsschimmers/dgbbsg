import 'dart:async';
import 'dart:collection';
import 'dart:io';

String redactLog(String text, [Iterable<String> secrets = const []]) {
  var result = text;
  for (final secret in secrets.where((s) => s.length >= 4)) {
    result = result.replaceAll(secret, '<凭据已隐藏>');
  }
  result = result.replaceAllMapped(RegExp(r'https?://[^\s）)]+'), (m) {
    final uri = Uri.tryParse(m[0]!);
    return uri == null ? '<URL 已隐藏>' : '${uri.scheme}://${uri.host}/<地址已隐藏>';
  });
  return result.replaceAll(RegExp(r'(Bearer\s+|(?:token|password|secret|uuid)\s*[=:]\s*)[^\s,;]+', caseSensitive: false), '<凭据已隐藏>');
}

/// 内存环形日志缓冲 + 流。UI 通过 Stream 订阅，按节流批量刷新，避免卡顿。
/// 使用 ListQueue 实现 O(1) 的头部淘汰（相比 List.removeAt(0) 的 O(n)）。
class AppLogger {
  final int maxLines;
  final _buffer = ListQueue<String>();
  final _controller = StreamController<String>.broadcast();
  final _clearController = StreamController<void>.broadcast();
  bool _disposed = false;
  final Set<String> _secrets = {};
  Directory? _directory;
  Future<void> _diskQueue = Future<void>.value();

  void registerSecrets(Iterable<String> values) => _secrets.addAll(values.where((v) => v.isNotEmpty));

  Future<void> enablePersistence(Directory directory) async {
    await directory.create(recursive: true);
    if (_disposed) return;
    _directory = directory;
    for (final line in snapshot) {
      _persist(line);
    }
  }

  void _persist(String line) {
    final directory = _directory;
    if (directory == null) return;
    _diskQueue = _diskQueue.then((_) async {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${directory.path}/run_$day.log');
      if (file.existsSync() && await file.length() > 1024 * 1024) {
        final rotated = File('${file.path}.1');
        if (rotated.existsSync()) await rotated.delete();
        await file.rename(rotated.path);
      }
      await file.writeAsString('${DateTime.now().toIso8601String()} $line\n', mode: FileMode.append, flush: true);
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      for (final old in directory.listSync().whereType<File>()) {
        if (RegExp(r'^run_\d{4}-\d{2}-\d{2}\.log(?:\.1)?$').hasMatch(old.uri.pathSegments.last) &&
            old.lastModifiedSync().isBefore(cutoff)) await old.delete();
      }
    }).catchError((Object _) {});
  }

  Future<void> flush() => _diskQueue;

  Future<String> exportTo(File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(snapshot.map((s) => redactLog(s, _secrets)).join('\n'), flush: true);
    return file.path;
  }

  AppLogger({this.maxLines = 2000});

  List<String> get snapshot => List.unmodifiable(_buffer);

  Stream<String> get stream => _controller.stream;
  Stream<void> get clearStream => _clearController.stream;

  void log(String line) {
    if (_disposed) return;
    line = redactLog(line, _secrets);
    _buffer.addLast(line);
    if (_buffer.length > maxLines) {
      _buffer.removeFirst();
    }
    _controller.add(line);
    _persist(line);
  }

  void info(String m) => log(m);
  void warning(String m) => log('[警告] $m');
  void success(String m) => log('[成功] $m');
  void error(String m) => log('[错误] $m');

  void clear() {
    if (_disposed) return;
    _buffer.clear();
    _clearController.add(null);
  }

  /// 关闭所有 StreamController，释放资源。调用后不可再 log/clear。
  void dispose() {
    _disposed = true;
    _controller.close();
    _clearController.close();
  }
}
