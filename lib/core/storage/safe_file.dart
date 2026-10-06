import 'dart:convert';
import 'dart:io';

/// Prepare flushed bytes beside the destination, then replace it. Keep a
/// recoverable previous copy until replacement succeeds (Windows included).
Future<void> safeWriteBytes(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final pending = File('${file.path}.pending');
  final previous = File('${file.path}.previous');
  await recoverSafeFile(file);
  await pending.writeAsBytes(bytes, flush: true);
  if (file.existsSync()) await file.rename(previous.path);
  try {
    await pending.rename(file.path);
  } catch (_) {
    if (previous.existsSync() && !file.existsSync()) {
      await previous.rename(file.path);
    }
    rethrow;
  }
  if (previous.existsSync()) await previous.delete();
}

Future<void> recoverSafeFile(File file) async {
  final previous = File('${file.path}.previous');
  if (!file.existsSync() && previous.existsSync()) {
    await previous.rename(file.path);
  } else if (file.existsSync() && previous.existsSync()) {
    await previous.delete();
  }
}

Future<void> safeWriteText(File file, String text) =>
    safeWriteBytes(file, utf8.encode(text));
