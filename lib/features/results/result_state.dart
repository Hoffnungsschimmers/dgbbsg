import 'dart:async';
import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/net/endpoint.dart';
import '../../core/net/push_quality.dart';
import '../../core/storage/result_files.dart';
import '../../core/storage/safe_file.dart';

/// 结果行。
/// 格式：`ip:port#注释`（注释为原始节点名称，如"精品v4 1"）
class ResultRow {
  final String node;

  /// 历史格式兼容：旧延迟优选输出会在行尾带 `50.00 ms`；当前流程不再产生延迟。
  final String? latency;
  final String evidence;
  ResultRow(this.node, [this.latency, this.evidence = '']);

  String get evidenceLabel => switch (evidence) {
    'cloudflare_trace' => 'POP 实测',
    'ip_geo_cache' || 'ip_geo_database' => 'GeoIP 估计',
    'cloudflare_trace_unknown_pop' => 'POP 国家未确认',
    'trace_unavailable' => '未确认',
    _ => '原始标注',
  };

  String get ipPort => node.split('#').first;

  /// # 后的全部内容 = 注释
  String get annotation {
    final hashIdx = node.indexOf('#');
    if (hashIdx < 0) return '';
    return node.substring(hashIdx + 1).trim();
  }

  /// 国家名称：注释中第一段（2字母大写）映射为中文名，如 "US mia" → "美国"
  String get country {
    final ann = annotation;
    if (ann.isEmpty) return '';
    // @ 分隔：US@cm → US
    if (ann.contains('@'))
      return countryCodeToName(ann.split('@').first.trim());
    // 空格分隔：US mia → US
    final parts = ann.split(RegExp(r'\s+'));
    final first = parts.first;
    if (RegExp(r'^[A-Z]{2}$').hasMatch(first)) return countryCodeToName(first);
    return '';
  }

  /// 来源/提供者：注释中国家码之后的部分；无国家码时为整个注释
  String get source {
    final ann = annotation;
    if (ann.isEmpty) return '';
    // @ 分隔：US@cm → cm
    if (ann.contains('@')) {
      final parts = ann.split('@');
      return parts.length > 1 ? parts.sublist(1).join('@').trim() : '';
    }
    // 空格分隔：US mia → mia；洛璃 → 洛璃
    final parts = ann.split(RegExp(r'\s+'));
    final first = parts.first;
    if (RegExp(r'^[A-Z]{2}$').hasMatch(first)) {
      return parts.length > 1 ? parts.sublist(1).join(' ').trim() : '';
    }
    // 无国家码前缀，整个注释就是来源
    return ann;
  }
}

/// 解析 ip.txt / addressesapi*.txt 内容为结果行。
/// 兼容新旧两种格式：
///   - 新格式（空格分隔）："1.2.3.4:443#US CM 50.00 ms"
///   - 旧格式（@ 分隔）：  "1.2.3.4:443#US@CM 50.00 ms"
///   - 纯节点："1.2.3.4:443#US" 或 "example.com:2053# 洛璃"
/// 已下线测速功能的旧行尾 "120.50 Mbps" 会被识别并丢弃，不污染节点与延迟。
List<ResultRow> parseResultLines(String text) {
  final rows = <ResultRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.contains(':')) continue;
    var parts = line.split(RegExp(r'\s+'));
    // 丢弃旧测速残留 token（如 "120.50 Mbps" 两 token 或 "120.50Mbps" 单 token），
    // 否则纯数字 token 会被误判为 "50.00 ms" 式延迟的数字半段。
    parts = parts.where((p) {
      if (p == 'Mbps') return false;
      if (RegExp(r'^\d+(\.\d+)?Mbps$').hasMatch(p)) return false;
      return true;
    }).toList();
    if (parts.isEmpty) continue;
    // 延迟部分只认行尾形态："50.00 ms"（两 token）或 "56.00ms"（单 token）。
    // 若行中出现「数字+ms」后面还有文字（例如备注「美国 120ms 优化专线」），
    // 不能当延迟切掉，否则其后的备注会在结果页保存时整段丢失。
    var latencyStart = -1;
    if (parts.length >= 2 &&
        parts.last == 'ms' &&
        RegExp(r'^\d+(\.\d+)?$').hasMatch(parts[parts.length - 2])) {
      latencyStart = parts.length - 2;
    } else if (RegExp(r'^\d+(\.\d+)?ms$').hasMatch(parts.last)) {
      latencyStart = parts.length - 1;
    }
    // 节点部分 = 延迟之前的全部 token（含来源与原始备注）
    final nodeEnd = latencyStart >= 0 ? latencyStart : parts.length;
    final node = bracketIpv6Host(parts.sublist(0, nodeEnd).join(' '));
    String? latency;
    if (latencyStart >= 0) {
      latency = parts.sublist(latencyStart).join(' ');
    }
    rows.add(ResultRow(node, latency));
  }
  return rows;
}

bool validResultNode(String node) {
  final ep = parseEndpoint(node);
  if (ep == null || ep.$1.isEmpty) return false;
  final host = ep.$1;
  if (InternetAddress.tryParse(host) != null) return true;
  if (RegExp(r'^[\d.]+$').hasMatch(host)) return false;
  return host.length <= 253 &&
      host
          .split('.')
          .every(
            (part) =>
                part.isNotEmpty &&
                part.length <= 63 &&
                RegExp(
                  r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$',
                ).hasMatch(part),
          );
}

class ResultState {
  final List<ResultRow> rows;
  final String? sourceLabel;
  final String? currentFile;
  final String? rawText;
  final String? generatedAt; // 上次生成时间（来自 .json 旁文件的 generated_at）
  final String searchQuery; // 搜索关键词
  final Map<String, dynamic> metadata;
  final bool canUndo;
  final bool canRedo;
  final bool dirty;
  final bool saving;
  final String? saveError;

  ResultState({
    this.rows = const [],
    this.sourceLabel,
    this.currentFile,
    this.rawText,
    this.generatedAt,
    this.searchQuery = '',
    this.metadata = const {},
    this.canUndo = false,
    this.canRedo = false,
    this.dirty = false,
    this.saving = false,
    this.saveError,
  });

  ResultState copyWith({
    List<ResultRow>? rows,
    String? sourceLabel,
    String? currentFile,
    String? rawText,
    String? generatedAt,
    String? searchQuery,
    bool clearFile = false,
    Map<String, dynamic>? metadata,
    bool? canUndo,
    bool? canRedo,
    bool? dirty,
    bool? saving,
    String? saveError,
    bool clearSaveError = false,
  }) => ResultState(
    rows: rows ?? this.rows,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    currentFile: clearFile ? null : (currentFile ?? this.currentFile),
    rawText: clearFile ? null : (rawText ?? this.rawText),
    generatedAt: clearFile ? null : (generatedAt ?? this.generatedAt),
    searchQuery: searchQuery ?? this.searchQuery,
    metadata: clearFile ? const {} : (metadata ?? this.metadata),
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    saveError: clearSaveError ? null : (saveError ?? this.saveError),
  );

  /// 过滤后的行：应用搜索
  List<ResultRow> get filteredRows {
    var result = rows;
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where(
            (r) =>
                r.ipPort.toLowerCase().contains(q) ||
                r.annotation.toLowerCase().contains(q),
          )
          .toList();
    }
    return result;
  }

  /// 序列化为文件/推送内容：每行 `node [latency]`，行序即列表顺序。
  String toText() {
    final sb = StringBuffer();
    for (final r in rows) {
      final parts = <String>[r.node];
      if (r.latency != null) parts.add(r.latency!);
      sb.writeln(parts.join(' '));
    }
    return sb.toString();
  }

  String? qualityIssue(AppConfig cfg) {
    final evidence = <String, String>{};
    for (final row in rows) {
      final ep = parseEndpoint(row.node);
      if (ep == null) return '结果包含无效地址，请先修正';
      evidence[ep.$1] = row.evidence;
    }
    return pushQualityIssue(
      nodes: evidence.isEmpty ? 0 : rows.length,
      totalIps: evidence.length,
      measured: evidence.values.where((v) => v == 'cloudflare_trace').length,
      estimated: evidence.values.where((v) => v.startsWith('ip_geo_')).length,
      previousNodes:
          int.tryParse(
            '${metadata['push_baseline_node_count'] ?? metadata['previous_node_count']}',
          ) ??
          0,
      minimumNodes: cfg.pushMinimumNodes,
      minimumMeasuredRatio: cfg.pushMinimumMeasuredRatio,
      minimumRetainedRatio: cfg.pushMinimumRetainedRatio,
    );
  }
}

class ResultNotifier extends StateNotifier<ResultState> {
  ResultNotifier() : super(ResultState());
  final _undo = <List<ResultRow>>[];
  final _redo = <List<ResultRow>>[];
  int _revision = 0;
  int _document = 0;
  int _loadRequest = 0;
  Future<void>? _saveQueue;

  void _resetHistory() {
    _undo.clear();
    _redo.clear();
    _document++;
    _revision++;
  }

  void _edit(List<ResultRow> rows, [String? label]) {
    if (rows.length == state.rows.length &&
        Iterable<int>.generate(rows.length).every(
          (i) =>
              rows[i].node == state.rows[i].node &&
              rows[i].latency == state.rows[i].latency &&
              rows[i].evidence == state.rows[i].evidence,
        ))
      return;
    _undo.add(List.of(state.rows));
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
    _revision++;
    state = state.copyWith(
      rows: List.unmodifiable(rows),
      sourceLabel: label,
      canUndo: true,
      canRedo: false,
      dirty: true,
      clearSaveError: true,
    );
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(List.of(state.rows));
    _revision++;
    state = state.copyWith(
      rows: _undo.removeLast(),
      canUndo: _undo.isNotEmpty,
      canRedo: true,
      dirty: true,
      clearSaveError: true,
    );
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(List.of(state.rows));
    _revision++;
    state = state.copyWith(
      rows: _redo.removeLast(),
      canUndo: true,
      canRedo: _redo.isNotEmpty,
      dirty: true,
      clearSaveError: true,
    );
  }

  /// Validate the whole draft before replacing any rows. Only an unchanged
  /// node keeps its measurement; a changed address or annotation needs a probe.
  void applyRawText(String text) {
    final rows = <ResultRow>[];
    final known = {for (final row in state.rows) row.node: row.evidence};
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parsed = parseResultLines(line);
      if (parsed.length != 1 || !validResultNode(parsed.single.node)) {
        throw FormatException('第 ${i + 1} 行不是有效的地址:端口');
      }
      final row = parsed.single;
      rows.add(ResultRow(row.node, row.latency, known[row.node] ?? ''));
    }
    _edit(rows);
  }

  void setRows(List<ResultRow> rows, [String? sourceLabel]) {
    _edit(rows, sourceLabel);
  }

  /// 从文件加载（用于「刷新」与单步执行后）。
  /// 同时保存原始文本，供「查看文件内容」面板使用。
  /// 若同名 .json 文件存在，读取其中的 generated_at 时间戳。
  Future<void> loadFile(String path) async {
    final request = ++_loadRequest;
    final revision = _revision;
    final resolved = resolveOutputPath(
      path,
      (await getApplicationDocumentsDirectory()).path,
    );
    final f = File(resolved);
    await recoverSafeFile(f);
    if (!f.existsSync()) {
      if (!mounted || request != _loadRequest || revision != _revision) return;
      _resetHistory();
      state = ResultState();
      return;
    }
    final text = await f.readAsString();

    // 尝试从 .json 旁文件读取生成时间戳
    final meta = await readResultMeta(f, text);
    final evidence = meta['landing_evidence'];
    final rows = parseResultLines(text).map((row) {
      final ep = parseEndpoint(row.node);
      final value = evidence is Map && ep != null
          ? evidence[ep.$1]?.toString() ?? ''
          : '';
      return ResultRow(row.node, row.latency, value);
    }).toList();

    if (!mounted || request != _loadRequest || revision != _revision) return;
    _resetHistory();
    state = ResultState(
      rows: rows,
      sourceLabel: path.split(RegExp(r'[\\/]')).last,
      currentFile: path,
      rawText: text,
      generatedAt: meta['generated_at']?.toString(),
      metadata: meta,
    );
  }

  /// 刷新当前文件：重载 `state.currentFile`，未加载过时用 [fallbackFile]。
  /// 统一「刷新按钮 / Ctrl+R / 启动加载」三条路径的目标文件语义。
  Future<void> refreshFile(String fallbackFile) async {
    final target = state.currentFile ?? fallbackFile;
    if (target.isEmpty) return;
    await loadFile(target);
  }

  /// 从节点行列表加载（单步：获取数据源 / 可用性结果）。
  void loadLines(List<String> lines, [String? label]) {
    final rows = lines
        .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
        .map((l) => ResultRow(bracketIpv6Host(l.trim())))
        .toList();
    _resetHistory();
    state = ResultState(rows: rows, sourceLabel: label);
  }

  /// 删除指定索引的节点。
  void removeRow(int index) {
    final rows = [...state.rows];
    if (index >= 0 && index < rows.length) {
      rows.removeAt(index);
      _edit(rows);
    }
  }

  /// 更新指定索引的节点行。
  void updateRow(int index, String rawLine) {
    final line = bracketIpv6Host(rawLine.trim());
    if (!validResultNode(line)) return;
    if (index < 0 || index >= state.rows.length) return;
    final rows = [...state.rows];
    final old = state.rows[index];
    rows[index] = ResultRow(
      line,
      old.latency,
      line == old.node ? old.evidence : '',
    );
    _edit(rows);
  }

  /// 添加一个节点行（原始格式：ip:port#CC 来源 备注）。
  void addRow(String rawLine) {
    final line = bracketIpv6Host(rawLine.trim());
    if (!validResultNode(line)) return;
    final rows = [...state.rows, ResultRow(line)];
    _edit(rows);
  }

  /// 设置搜索关键词。
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// 拖拽排序：将 [oldIndex] 处的行移动到 [newIndex]。
  void reorderRow(int oldIndex, int newIndex) {
    final rows = [...state.rows];
    if (oldIndex < 0 || oldIndex >= rows.length || newIndex < 0) return;
    if (newIndex > rows.length) newIndex = rows.length;
    if (newIndex > oldIndex) newIndex--;
    final row = rows.removeAt(oldIndex);
    rows.insert(newIndex, row);
    _edit(rows);
  }

  /// 将当前节点列表写回文件（覆盖）。
  Future<void> saveToFile() async {
    final captured = state;
    final document = _document;
    final revision = _revision;
    final path = captured.currentFile;
    if (path == null) return;
    final text = captured.toText();
    final evidence = <String, String>{};
    for (final row in captured.rows) {
      final ep = parseEndpoint(row.node);
      if (ep != null && row.evidence.isNotEmpty) evidence[ep.$1] = row.evidence;
    }
    final meta = {
      ...captured.metadata,
      'node_count': captured.rows.length,
      'landing_evidence': evidence,
      'edited_at': DateTime.now().toIso8601String(),
    };
    state = state.copyWith(saving: true, clearSaveError: true);
    final previous = _saveQueue;
    final done = Completer<void>();
    _saveQueue = done.future;
    try {
      if (previous != null) await previous;
      final resolved = resolveOutputPath(
        path,
        (await getApplicationDocumentsDirectory()).path,
      );
      await writeResultBundle(File(resolved), text, meta);
      if (mounted && document == _document && revision == _revision) {
        state = state.copyWith(
          rawText: text,
          metadata: meta,
          dirty: false,
          saving: false,
          clearSaveError: true,
        );
      }
    } catch (e) {
      if (mounted && document == _document && revision == _revision) {
        state = state.copyWith(saving: false, dirty: true, saveError: '$e');
      }
      rethrow;
    } finally {
      done.complete();
      if (identical(_saveQueue, done.future)) {
        _saveQueue = null;
        if (mounted && document == _document)
          state = state.copyWith(saving: false);
      }
    }
  }

  Future<List<File>> snapshots() async {
    if (state.currentFile == null) return [];
    final target = resolveOutputPath(
      state.currentFile!,
      (await getApplicationDocumentsDirectory()).path,
    );
    final dir = Directory('${File(target).parent.path}/history');
    if (!dir.existsSync()) return [];
    final matches = <File>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.uri.pathSegments.last.startsWith('landing_') ||
          !file.path.endsWith('.txt'))
        continue;
      final meta = await readResultMeta(file, await file.readAsString());
      if (meta['snapshot_target'] == File(target).absolute.path)
        matches.add(file);
    }
    matches.sort((a, b) => b.path.compareTo(a.path));
    return matches;
  }

  Future<void> restoreSnapshot(File snapshot) async {
    final current = state.currentFile;
    if (current == null ||
        !(await snapshots()).any((f) => f.path == snapshot.path)) {
      throw StateError('快照不属于当前结果文件');
    }
    final text = await snapshot.readAsString();
    final meta = await readResultMeta(snapshot, text);
    meta.remove('snapshot_target');
    final resolved = resolveOutputPath(
      current,
      (await getApplicationDocumentsDirectory()).path,
    );
    await writeResultBundle(File(resolved), text, {
      ...meta,
      'restored_at': DateTime.now().toIso8601String(),
    });
    await loadFile(current);
  }
}

final resultProvider = StateNotifierProvider<ResultNotifier, ResultState>(
  (ref) => ResultNotifier(),
);
