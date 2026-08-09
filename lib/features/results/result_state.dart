import 'dart:convert';
import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 从 "50.00 ms" 或 "50.00ms" 提取数值。统一的延迟解析函数。
double? parseLatency(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
}

/// 结果行（对应旧版 ResultsPanel 的表格行）。
/// 兼容新旧格式：`ip:port#CC source` 或 `ip:port#CC@source`
class ResultRow {
  final String node;
  final String? latency; // "50.00 ms" 或 null
  ResultRow(this.node, [this.latency]);

  String get ipPort => node.split('#').first;
  String get country => countryCodeToName(nodeCountry(node));
  String get source {
    final hashIdx = node.indexOf('#');
    if (hashIdx < 0) return '';
    final afterHash = node.substring(hashIdx + 1);
    // 优先找空格（新格式），再找 @（旧格式）
    final spaceIdx = afterHash.indexOf(' ');
    final atIdx = afterHash.indexOf('@');
    int sepIdx = -1;
    if (spaceIdx >= 0 && (atIdx < 0 || spaceIdx < atIdx)) {
      sepIdx = spaceIdx;
    } else if (atIdx >= 0) {
      sepIdx = atIdx;
    }
    if (sepIdx < 0) return '';
    return afterHash.substring(sepIdx + 1).trim();
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
    final node = parts.sublist(0, nodeEnd).join(' ');
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
  ResultState({this.rows = const [], this.sourceLabel, this.currentFile, this.rawText, this.generatedAt});
  ResultState copyWith({
    List<ResultRow>? rows,
    String? sourceLabel,
    String? currentFile,
    String? rawText,
    String? generatedAt,
    bool clearFile = false,
  }) =>
      ResultState(
        rows: rows ?? this.rows,
        sourceLabel: sourceLabel ?? this.sourceLabel,
        currentFile: clearFile ? null : (currentFile ?? this.currentFile),
        rawText: clearFile ? null : (rawText ?? this.rawText),
        generatedAt: clearFile ? null : (generatedAt ?? this.generatedAt),
      );
}

class ResultNotifier extends StateNotifier<ResultState> {
  ResultNotifier() : super(ResultState());

  void setRows(List<ResultRow> rows, [String? sourceLabel]) {
    state = state.copyWith(rows: rows, sourceLabel: sourceLabel);
  }

  /// 从文件加载（用于「刷新」与单步执行后）。
  /// 同时保存原始文本，供「查看文件内容」面板使用。
  /// 若同名 .json 文件存在，读取其中的 generated_at 时间戳。
  Future<void> loadFile(String path) async {
    final resolved = resolveOutputPath(path, (await getApplicationDocumentsDirectory()).path);
    final f = File(resolved);
    if (!f.existsSync()) {
      state = state.copyWith(clearFile: true);
      return;
    }
    final text = await f.readAsString();

    // 尝试从 .json 旁文件读取优选时间戳
    String? generatedAt;
    final jsonFile = File('$resolved.json');
    if (jsonFile.existsSync()) {
      try {
        final jsonData = jsonDecode(await jsonFile.readAsString());
        if (jsonData is Map && jsonData['generated_at'] != null) {
          generatedAt = jsonData['generated_at'].toString();
        }
      } catch (_) {}
    }

    state = ResultState(
      rows: parseResultLines(text),
      sourceLabel: path.split(RegExp(r'[\\/]')).last,
      currentFile: path,
      rawText: text,
      generatedAt: generatedAt,
    );
  }

  /// 从节点行列表加载（单步：获取数据源 / 可用性结果）。
  void loadLines(List<String> lines, [String? label]) {
    final rows = lines
        .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
        .map((l) => ResultRow(l.trim()))
        .toList();
    state = state.copyWith(rows: rows, sourceLabel: label);
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
    final line = rawLine.trim();
    if (line.isEmpty || !line.contains(':')) return;
    if (index < 0 || index >= state.rows.length) return;
    final rows = [...state.rows];
    rows[index] = ResultRow(line, state.rows[index].latency);
    state = state.copyWith(rows: rows);
  }

  /// 添加一个节点行（原始格式：ip:port#CC source）。
  void addRow(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.contains(':')) return;
    final rows = [...state.rows, ResultRow(line)];
    state = state.copyWith(rows: rows);
  }

  /// 将当前节点列表写回文件（覆盖）。
  Future<void> saveToFile() async {
    final path = state.currentFile;
    if (path == null) return;
    final resolved = resolveOutputPath(path, (await getApplicationDocumentsDirectory()).path);
    final sb = StringBuffer();
    for (final r in state.rows) {
      // 用原始 node 字符串重建行，保留国家码和来源
      final parts = <String>[r.node];
      if (r.latency != null) parts.add(r.latency!);
      sb.writeln(parts.join(' '));
    }
    await File(resolved).writeAsString(sb.toString());
    // 同步更新 rawText
    state = state.copyWith(rawText: sb.toString());
  }
}

final resultProvider = StateNotifierProvider<ResultNotifier, ResultState>(
  (ref) => ResultNotifier(),
);
