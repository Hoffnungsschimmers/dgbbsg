import 'dart:async';
import 'dart:io';

import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/core/storage/result_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import '../../helpers/temp_dir.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  Completer<String?>? next;
  @override
  Future<String?> getApplicationDocumentsPath() {
    final pending = next;
    next = null;
    return pending?.future ?? Future.value(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late _Paths paths;
  late PathProviderPlatform original;
  late ResultNotifier notifier;
  setUp(() async {
    original = PathProviderPlatform.instance;
    dir = await Directory.systemTemp.createTemp('cfnb_edit_');
    paths = _Paths(dir.path);
    PathProviderPlatform.instance = paths;
    notifier = ResultNotifier();
  });
  tearDown(() async {
    notifier.dispose();
    PathProviderPlatform.instance = original;
    await removeTempDir(dir);
  });

  Future<File> seed(String name, String text) async {
    final f = File('${dir.path}/$name');
    await writeResultBundle(f, text, {
      'landing_evidence': {'1.1.1.1': 'cloudflare_trace'},
    }, snapshot: false);
    await notifier.loadFile(name);
    return f;
  }

  test('unchanged raw round trip keeps evidence and creates no edit', () async {
    await seed('a.txt', '1.1.1.1:443#US source\n');
    notifier.applyRawText(notifier.state.toText());
    expect(notifier.state.rows.single.evidence, 'cloudflare_trace');
    expect(notifier.state.canUndo, isFalse);
    expect(notifier.state.dirty, isFalse);
  });

  test('raw validation is atomic and preserves line number', () async {
    await seed('a.txt', '1.1.1.1:443#US source\n');
    expect(
      () => notifier.applyRawText('2.2.2.2:443\ninvalid\n'),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'line', contains('2')),
      ),
    );
    expect(notifier.state.rows.single.ipPort, '1.1.1.1:443');
    expect(notifier.state.dirty, isFalse);
    for (final line in [
      '999.1.1.1:443',
      ':443',
      'example.com:70000',
      '[bad::ip]:443',
    ]) {
      expect(() => notifier.applyRawText(line), throwsFormatException);
    }
  });

  test(
    'changed annotation loses evidence; undo and redo restore exact rows',
    () async {
      final file = await seed('a.txt', '1.1.1.1:443#US source\n');
      notifier.updateRow(0, '1.1.1.1:443#HK changed');
      expect(notifier.state.rows.single.evidence, isEmpty);
      await notifier.saveToFile();
      notifier.undo();
      expect(notifier.state.rows.single.evidence, 'cloudflare_trace');
      await notifier.saveToFile();
      expect(await file.readAsString(), '1.1.1.1:443#US source\n');
      notifier.redo();
      expect(notifier.state.rows.single.annotation, 'HK changed');
      notifier.addRow('2.2.2.2:443');
      expect(notifier.state.canRedo, isFalse);
    },
  );

  test('saving captures file and rows before path resolution', () async {
    final first = await seed('a.txt', '1.1.1.1:443\n');
    notifier.addRow('2.2.2.2:443');
    final gate = Completer<String?>();
    paths.next = gate;
    final saving = notifier.saveToFile();
    final second = File('${dir.path}/b.txt');
    await second.writeAsString('3.3.3.3:443\n');
    await notifier.loadFile('b.txt');
    gate.complete(dir.path);
    await saving;
    expect(await first.readAsString(), '1.1.1.1:443\n2.2.2.2:443\n');
    expect(notifier.state.currentFile, 'b.txt');
    expect(notifier.state.rawText, '3.3.3.3:443\n');
    expect(notifier.state.rows.single.ipPort, '3.3.3.3:443');
  });

  test('queued saves finish with latest content and metadata', () async {
    final file = await seed('a.txt', '1.1.1.1:443\n');
    notifier.addRow('2.2.2.2:443');
    final gate = Completer<String?>();
    paths.next = gate;
    final first = notifier.saveToFile();
    notifier.addRow('3.3.3.3:443');
    final second = notifier.saveToFile();
    gate.complete(dir.path);
    await Future.wait([first, second]);
    expect(await file.readAsString(), notifier.state.toText());
    expect(notifier.state.rows, hasLength(3));
    expect(notifier.state.saving, isFalse);
    expect(notifier.state.dirty, isFalse);
    final meta = await readResultMeta(file, await file.readAsString());
    expect(meta['node_count'], 3);
  });

  test('failed save retains dirty edits and supports retry', () async {
    final file = await seed('a.txt', '1.1.1.1:443\n');
    notifier.addRow('2.2.2.2:443');
    final gate = Completer<String?>();
    paths.next = gate;
    final saving = notifier.saveToFile();
    final check = expectLater(saving, throwsA(isA<FileSystemException>()));
    gate.completeError(const FileSystemException('test path failure'));
    await check;
    expect(notifier.state.dirty, isTrue);
    expect(notifier.state.saving, isFalse);
    expect(notifier.state.saveError, contains('test path failure'));
    await notifier.saveToFile();
    expect(notifier.state.saveError, isNull);
    expect(notifier.state.dirty, isFalse);
    expect(await file.readAsString(), notifier.state.toText());
  });

  test(
    'undo history is bounded and resets after loading another file',
    () async {
      await seed('a.txt', '1.1.1.1:443\n');
      for (var i = 0; i < 40; i++) {
        notifier.addRow('2.2.2.2:${1000 + i}');
      }
      var undone = 0;
      while (notifier.state.canUndo) {
        notifier.undo();
        undone++;
      }
      expect(undone, 30);
      await notifier.loadFile('a.txt');
      expect(notifier.state.canRedo, isFalse);
      expect(notifier.state.canUndo, isFalse);
    },
  );
}
