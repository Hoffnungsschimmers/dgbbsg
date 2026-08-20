import 'dart:async';
import 'dart:collection';

/// 内存环形日志缓冲 + 流。UI 通过 Stream 订阅，按节流批量刷新，避免卡顿。
/// 使用 ListQueue 实现 O(1) 的头部淘汰（相比 List.removeAt(0) 的 O(n)）。
class AppLogger {
  final int maxLines;
  final _buffer = ListQueue<String>();
  final _controller = StreamController<String>.broadcast();
  final _clearController = StreamController<void>.broadcast();
  bool _disposed = false;

  AppLogger({this.maxLines = 2000});

  List<String> get snapshot => List.unmodifiable(_buffer);

  Stream<String> get stream => _controller.stream;
  Stream<void> get clearStream => _clearController.stream;

  void log(String line) {
    if (_disposed) return;
    _buffer.addLast(line);
    if (_buffer.length > maxLines) {
      _buffer.removeFirst();
    }
    _controller.add(line);
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
