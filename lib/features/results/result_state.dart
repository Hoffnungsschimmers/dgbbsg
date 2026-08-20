import 'dart:convert';
import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 从 "50.00 ms" 或 "50.00ms" 提取数值。统一的延迟解析函数。
double? parseLatency(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
}

/// 结果行。
/// 格式：`ip:port#注释`（注释为原始节点名称，如"精品v4 1"）
class ResultRow {
  final String node;
  final String? latency;
  final String? jitter;
  ResultRow(this.node, [this.latency, this.jitter]);

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
    if (ann.contains('@')) return countryCodeToName(ann.split('@').first.trim());
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
List<ResultRow> parseResultLines(String text) {
  final rows = <ResultRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (!line.contains(':')) continue;
    final parts = line.split(RegExp(r'\s+'));
    // 找到延迟部分：可能 "50.00 ms"（两个 token）或 "56.00ms"（一个 token）
    // 延迟 token 特征：含 'ms' 或者是紧跟在含 'ms' token 前面的纯数字
    var latencyStart = -1; // 延迟数字开始的 index
    for (var i = 1; i < parts.length; i++) {
      if (parts[i].contains('ms')) {
        // "50.00 ms" 模式：前一个是数字
        if (i > 0 && RegExp(r'^\d').hasMatch(parts[i - 1])) {
          latencyStart = i - 1;
        } else {
          // "56.00ms" 模式：这个 token 自己就是延迟
          latencyStart = i;
        }
        break;
      }
    }
    // 节点部分 = 延迟之前的全部 token（含来源）
    final nodeEnd = latencyStart >= 0 ? latencyStart : parts.length;
    final node = bracketIpv6Host(parts.sublist(0, nodeEnd).join(' '));
    String? latency;
    if (latencyStart >= 0) {
      if (latencyStart + 1 < parts.length && parts[latencyStart + 1].contains('ms')) {
        latency = '${parts[latencyStart]} ${parts[latencyStart + 1]}';
      } else {
        latency = parts[latencyStart];
      }
    }
    rows.add(ResultRow(node, latency));
  }
  return rows;
}

class ResultState {
  final List<ResultRow> rows;
  final String? sourceLabel;
  final String? currentFile;
  final String? rawText;
  final String? generatedAt; // 上次优选时间（来自 JSON 的 generated_at）
  final String searchQuery; // 搜索关键词

  ResultState({
    this.rows = const [],
    this.sourceLabel,
    this.currentFile,
    this.rawText,
    this.generatedAt,
    this.searchQuery = '',
  });

  ResultState copyWith({
    List<ResultRow>? rows,
    String? sourceLabel,
    String? currentFile,
    String? rawText,
    String? generatedAt,
    String? searchQuery,
    bool clearFile = false,
  }) =>
      ResultState(
        rows: rows ?? this.rows,
        sourceLabel: sourceLabel ?? this.sourceLabel,
        currentFile: clearFile ? null : (currentFile ?? this.currentFile),
        rawText: clearFile ? null : (rawText ?? this.rawText),
        generatedAt: clearFile ? null : (generatedAt ?? this.generatedAt),
        searchQuery: searchQuery ?? this.searchQuery,
      );

  /// 过滤后的行：应用搜索
  List<ResultRow> get filteredRows {
    var result = rows;
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((r) =>
              r.ipPort.toLowerCase().contains(q) ||
              r.annotation.toLowerCase().contains(q))
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
}

class ResultNotifier extends StateNotifier<ResultState> {
  ResultNotifier() : super(ResultState());

  void setRows(List<ResultRow> rows, [String? sourceLabel]) {
    state = state.copyWith(rows: rows, sourceLabel: sourceLabel);
  }

  /// 从文件加载（用于「刷新」与单步执行后）。
  /// 同时保存原始文本，供「查看文件内容」面板使用。
  /// 若同名 .json 文件存在，读取其中的 generated_at 时间戳和 jitter_ms 数据。
  Future<void> loadFile(String path) async {
    final resolved = resolveOutputPath(path, (await getApplicationDocumentsDirectory()).path);
    final f = File(resolved);
    if (!f.existsSync()) {
      state = state.copyWith(clearFile: true, searchQuery: '');
      return;
    }
    final text = await f.readAsString();

    // 尝试从 .json 旁文件读取优选时间戳和抖动数据
    String? generatedAt;
    final jitterMap = <String, double>{}; // ip:port -> jitter_ms
    final jsonFile = File('$resolved.json');
    if (jsonFile.existsSync()) {
      try {
        final jsonData = jsonDecode(await jsonFile.readAsString());
        if (jsonData is Map) {
          if (jsonData['generated_at'] != null) {
            generatedAt = jsonData['generated_at'].toString();
          }
          final nodes = jsonData['nodes'] as List?;
          if (nodes != null) {
            for (final n in nodes) {
              if (n is! Map) continue;
              final ip = n['ip'] as String? ?? '';
              final port = n['port'] as int? ?? 0;
              final jitter = (n['jitter_ms'] as num?)?.toDouble();
              if (ip.isNotEmpty && port > 0 && jitter != null) {
                jitterMap[bracketIpv6Host('$ip:$port')] = jitter;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 解析行并填充抖动数据
    var rows = parseResultLines(text);
    if (jitterMap.isNotEmpty) {
      rows = rows.map((r) {
        final jitter = jitterMap[r.ipPort];
        if (jitter != null) {
          return ResultRow(r.node, r.latency, '${jitter.toStringAsFixed(2)} ms');
        }
        return r;
      }).toList();
    }

    state = ResultState(
      rows: rows,
      sourceLabel: path.split(RegExp(r'[\\/]')).last,
      currentFile: path,
      rawText: text,
      generatedAt: generatedAt,
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
    state = state.copyWith(rows: rows, sourceLabel: label, searchQuery: '');
  }

  /// 删除指定索引的节点。
  void removeRow(int index) {
    final rows = [...state.rows];
    if (index >= 0 && index < rows.length) {
      rows.removeAt(index);
      state = state.copyWith(rows: rows);
    }
  }

  /// 更新指定索引的节点行。
  void updateRow(int index, String rawLine) {
    final line = bracketIpv6Host(rawLine.trim());
    if (line.isEmpty || !line.contains(':')) return;
    if (index < 0 || index >= state.rows.length) return;
    final rows = [...state.rows];
    rows[index] = ResultRow(line, state.rows[index].latency);
    state = state.copyWith(rows: rows);
  }

  /// 添加一个节点行（原始格式：ip:port#CC source）。
  void addRow(String rawLine) {
    final line = bracketIpv6Host(rawLine.trim());
    if (line.isEmpty || !line.contains(':')) return;
    final rows = [...state.rows, ResultRow(line)];
    state = state.copyWith(rows: rows);
  }

  /// 设置搜索关键词。
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// 拖拽排序：将 [oldIndex] 处的行移动到 [newIndex]。
  void reorderRow(int oldIndex, int newIndex) {
    final rows = [...state.rows];
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex > rows.length) newIndex = rows.length;
    if (newIndex > oldIndex) newIndex--;
    final row = rows.removeAt(oldIndex);
    rows.insert(newIndex, row);
    state = state.copyWith(rows: rows);
  }

  /// 将当前节点列表写回文件（覆盖）。
  Future<void> saveToFile() async {
    final path = state.currentFile;
    if (path == null) return;
    final resolved = resolveOutputPath(path, (await getApplicationDocumentsDirectory()).path);
    final text = state.toText();
    await File(resolved).writeAsString(text);
    // 同步更新 rawText
    state = state.copyWith(rawText: text);
  }
}

final resultProvider = StateNotifierProvider<ResultNotifier, ResultState>(
  (ref) => ResultNotifier(),
);
