import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../net/landing_history.dart';
import 'safe_file.dart';

final _writes = <String, Future<void>>{};

String resultHash(String text) => sha256.convert(utf8.encode(text)).toString();

/// Serialize writers of a result bundle. A content hash prevents readers from
/// applying a stale sidecar if a process exits between the two replacements.
Future<void> writeResultBundle(
  File file,
  String text,
  Map<String, Object?> meta, {
  bool snapshot = true,
}) async {
  final key = file.absolute.path;
  final before = _writes[key] ?? Future<void>.value();
  final operation = before.then((_) async {
    await recoverSafeFile(file);
    if (snapshot) {
      snapshotLandingOutput(
        file,
        Directory('${file.parent.path}/history'),
        DateTime.now().toIso8601String(),
      );
    }
    await safeWriteText(file, text);
    await safeWriteText(
      File('${file.path}.json'),
      jsonEncode({...meta, 'content_sha256': resultHash(text)}),
    );
  });
  final settled = operation.then<void>(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  _writes[key] = settled;
  try {
    await operation;
  } finally {
    if (identical(_writes[key], settled)) _writes.remove(key);
  }
}

Future<Map<String, dynamic>> readResultMeta(File file, String text) async {
  final sidecar = File('${file.path}.json');
  await recoverSafeFile(sidecar);
  if (!sidecar.existsSync()) return {};
  try {
    final data = jsonDecode(await sidecar.readAsString());
    if (data is! Map<String, dynamic>) return {};
    if (data['content_sha256'] != null &&
        data['content_sha256'] != resultHash(text))
      return {};
    return data;
  } catch (_) {
    return {};
  }
}

Future<void> markResultPushed(File file, String text) async {
  if (!file.existsSync() || await file.readAsString() != text) return;
  final meta = await readResultMeta(file, text);
  await safeWriteText(
    File('${file.path}.json'),
    jsonEncode({
      ...meta,
      'content_sha256': resultHash(text),
      'push_baseline_node_count': text
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
          .length,
      'pushed_at': DateTime.now().toIso8601String(),
    }),
  );
}
