import 'dart:io';

/// 删除用例临时目录，容忍 Windows 上的短暂占用。
///
/// 用例刚写完文件就删目录时，杀软/索引可能还持有句柄，`delete(recursive: true)`
/// 偶发抛 `PathAccessException errno=32`，把一条逻辑完全正确的用例判红——全量并行跑时
/// 最容易撞上（单跑同一文件恒过）。清理临时目录不是被测行为，重试耗尽后放弃即可，
/// 真实缺陷仍由用例自身的 expect 暴露。
///
/// `test()` 与 `testWidgets` 都能用：tearDown 里的 `Future.delayed` 由真实时钟推进，
/// 仓库原本就有手写的 5 次重试循环（`results_tab_test.dart`），这里统一成一处。
Future<void> removeTempDir(Directory dir) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
