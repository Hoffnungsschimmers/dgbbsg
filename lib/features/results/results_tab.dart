import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/platform.dart';
import '../../app/theme.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/net/ip.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';
import '../subscriptions/subscriptions_state.dart';
import 'result_state.dart';
import '../../core/config/app_config.dart';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════
// 国旗 emoji 辅助
// ═══════════════════════════════════════════════════════

/// 国家码/中文名 → 国旗 emoji（Regional Indicator Symbol 对）。
/// 例：'HK' → 🇭🇰，'US' → 🇺🇸，'香港' → 🇭🇰。非 ASCII 或空返回空串。
String countryCodeToFlag(String input) {
  String cc = input;
  if (input.length != 2 || input.codeUnitAt(0) > 127) {
    cc = normalizeCountryCode(input);
  }
  if (cc.length != 2) return '';
  final a = cc.codeUnitAt(0);
  final b = cc.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCode(0x1F1E6 + a - 65) + String.fromCharCode(0x1F1E6 + b - 65);
}

// ═══════════════════════════════════════════════════════
// ResultsTab
// ═══════════════════════════════════════════════════════

class ResultsTab extends ConsumerStatefulWidget {
  const ResultsTab({super.key});
  @override
  ConsumerState<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends ConsumerState<ResultsTab> with AutomaticKeepAliveClientMixin {
  String? _selectedFile;
  bool _rawView = false;
  bool _pushing = false;
  bool _editMode = false;
  final _addNodeCtrl = TextEditingController();

  // 排序状态
  int _sortCol = 1; // 默认按延迟列排序
  bool _sortAsc = true;

  // 缓存存在性检查结果
  List<String> _existingCandidates = [];

  @override
  bool get wantKeepAlive => true;

  Future<void> _refreshCandidates(AppConfig? cfg) async {
    final names = <String>[
      cfg?.subOutputFile ?? 'addressesapi.txt',
      cfg?.subLatencyOutputFile ?? 'addressesapi_top.txt',
    ].where((p) => p.isNotEmpty).toSet().toList();
    final dir = (await getApplicationDocumentsDirectory()).path;
    final paths = names.map((n) => resolveOutputPath(n, dir)).toList();
    final existing = <String>[];
    for (var i = 0; i < names.length; i++) {
      if (File(paths[i]).existsSync()) existing.add(names[i]);
    }
    if (!mounted) return;
    setState(() {
      _existingCandidates = existing;
    });
  }

  @override
  void dispose() {
    _addNodeCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshCandidates(ref.read(configProvider).value);
    ref.listenManual(configProvider, (_, next) {
      _refreshCandidates(next.value);
    });
  }

  static Map<String, int> _geoDistribution(List<ResultRow> rows) {
    final map = <String, int>{};
    for (final r in rows) {
      final c = r.country.isEmpty ? '未知' : r.country;
      map[c] = (map[c] ?? 0) + 1;
    }
    return map;
  }

  static double? _lowestLatency(List<ResultRow> rows) {
    double? low;
    for (final r in rows) {
      final v = parseLatency(r.latency);
      if (v != null && (low == null || v < low)) low = v;
    }
    return low;
  }

  List<ResultRow> _sortRows(List<ResultRow> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 0:
          cmp = a.ipPort.compareTo(b.ipPort);
          break;
        case 1:
          final la = parseLatency(a.latency);
          final lb = parseLatency(b.latency);
          if (la == null && lb == null) return 0;
          if (la == null) return 1;
          if (lb == null) return -1;
          cmp = la.compareTo(lb);
          break;
        case 2:
          cmp = a.country.compareTo(b.country);
          break;
        case 3:
          cmp = a.source.compareTo(b.source);
          break;
        default:
          cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  /// 弹出编辑对话框，修改节点的 ip:port 或来源。
  void _showEditDialog(int originalIndex, ResultRow row) {
    final ipPortCtl = TextEditingController(text: row.ipPort);
    final sourceCtl = TextEditingController(text: row.source);
    final latencyCtl = TextEditingController(text: row.latency ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppThemeExt.of(ctx);
        return AlertDialog(
          title: const Text('编辑节点'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ipPortCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'IP:端口',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sourceCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: '来源',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latencyCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: '延迟（如 50.00 ms）',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final ipPort = ipPortCtl.text.trim();
                final source = sourceCtl.text.trim();
                final latency = latencyCtl.text.trim();
                if (ipPort.isNotEmpty) {
                  // 重建 node：ipPort#countryCode source
                  final cc = nodeCountry(row.node);
                  final ccPart = cc.isNotEmpty ? '#$cc' : '';
                  final srcPart = source.isNotEmpty ? ' $source' : '';
                  final newNode = '$ipPort$ccPart$srcPart';
                  // 通过读取 provider state 获取当前行列表
                  final currentRows = [...ref.read(resultProvider).rows];
                  if (originalIndex < currentRows.length) {
                    currentRows[originalIndex] = ResultRow(newNode, latency.isNotEmpty ? latency : null);
                    ref.read(resultProvider.notifier).setRows(currentRows, ref.read(resultProvider).sourceLabel);
                  }
                  ref.read(resultProvider.notifier).saveToFile();
                }
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppThemeExt.of(context);
    final state = ref.watch(resultProvider);
    final cfgAsync = ref.watch(configProvider);

    final candidates = _existingCandidates;
    _selectedFile ??= state.currentFile ?? (candidates.isNotEmpty ? candidates.first : null);
    final effectiveSelected =
        (_selectedFile != null && candidates.contains(_selectedFile))
            ? _selectedFile!
            : (candidates.isNotEmpty ? candidates.first : null);

    final rows = state.rows;
    final sortedRows = _sortRows(rows);
    final geo = _geoDistribution(rows);
    final lowestLatency = _lowestLatency(rows);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth > 1100 ? 1080.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 标题栏 ──
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Text('优选结果',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              )),
                      if (state.sourceLabel != null)
                        pill(context, state.sourceLabel!, t.surfaceHover),
                      if (state.generatedAt != null)
                        pillWithIcon(context, icon: Icons.schedule, text: state.generatedAt!, bg: t.surfaceHover),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新',
                        onPressed: () async {
                          final cfg = cfgAsync.value;
                          if (cfg != null) {
                            _selectedFile = cfg.subLatencyOutputFile;
                            _rawView = false;
                            setState(() {});
                            await ref.read(resultProvider.notifier).loadFile(cfg.subLatencyOutputFile);
                          }
                        },
                      ),
                      IconButton.filledTonal(
                        icon: Icon(_editMode ? Icons.edit_off : Icons.edit),
                        tooltip: _editMode ? '退出编辑' : '编辑节点',
                        onPressed: () => setState(() => _editMode = !_editMode),
                      ),
                      _pushGithubButton(context, cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt'),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── 文件选择 + 视图切换 ──
                  if (candidates.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: SegmentedButton<String>(
                            selected: {effectiveSelected ?? candidates.first},
                            onSelectionChanged: (s) async {
                              final v = s.first;
                              _selectedFile = v;
                              setState(() {});
                              await ref.read(resultProvider.notifier).loadFile(v);
                            },
                            segments: candidates
                                .map((c) => ButtonSegment(
                                      value: c,
                                      label: Text(c, style: const TextStyle(fontFamily: 'AppMono', fontSize: 14)),
                                    ))
                                .toList(),
                          ),
                        ),
                        ToggleButtons(
                          isSelected: [!_rawView, _rawView],
                          borderRadius: t.radius,
                          selectedColor: Colors.white,
                          fillColor: AppTheme.edgeOrange,
                          color: t.textDim,
                          onPressed: (i) => setState(() => _rawView = i == 1),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('解析视图', style: TextStyle(fontSize: 14))),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('原始内容', style: TextStyle(fontSize: 14))),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),

                  // ── 空状态 ──
                  if (rows.isEmpty && !_rawView)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 32),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: t.radius,
                        border: Border.all(color: t.border, width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppTheme.edgeOrange.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.inbox_outlined, size: 36, color: AppTheme.edgeOrange.withValues(alpha: 0.6)),
                          )
                              .animate(delay: 0.ms)
                              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
                              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: Motion.staggerDur, curve: Motion.curveStandard),
                          const SizedBox(height: 20),
                          Text('暂无结果',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: t.text))
                              .animate(delay: 80.ms)
                              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
                              .slideY(begin: 0.2, end: 0, duration: Motion.staggerDur, curve: Motion.curveStandard),
                          const SizedBox(height: 10),
                          Text('运行「订阅IP」和「延迟优选」后，结果会显示在这里。',
                              style: TextStyle(color: t.textDim, fontSize: 14))
                              .animate(delay: 160.ms)
                              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
                              .slideY(begin: 0.2, end: 0, duration: Motion.staggerDur, curve: Motion.curveStandard),
                        ],
                      ),
                    )

                  // ── 原始内容视图 ──
                  else if (_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                          minHeight: 200,
                        ),
                        child: (state.rawText == null || state.currentFile != _selectedFile)
                            ? Center(child: Text('加载中…', style: TextStyle(color: t.textDim, fontSize: 14)))
                            : RawTextView(state.rawText!, copyTooltip: '复制文件内容'),
                      ),
                    )

                  // ── 解析视图 ──
                  else ...[
                    // 统计卡片区
                    ResultStatsRow(rows: rows, geo: geo, lowestLatency: lowestLatency),
                    const SizedBox(height: 20),

                    // 国家/地区分布
                    if (geo.length > 1) ...[
                      card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('国家 / 地区分布',
                                style: TextStyle(color: t.textDim, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: geo.entries
                                  .map((e) => _GeoChip(
                                        code: e.key,
                                        count: e.value,
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 数据表格
                    ResultTable(
                      rows: sortedRows,
                      editMode: _editMode,
                      sortCol: _sortCol,
                      sortAsc: _sortAsc,
                      onSort: (col) {
                        setState(() {
                          if (_sortCol == col) {
                            _sortAsc = !_sortAsc;
                          } else {
                            _sortCol = col;
                            _sortAsc = true;
                          }
                        });
                      },
                      onEdit: (i) {
                        final originalIdx = rows.indexOf(sortedRows[i]);
                        if (originalIdx >= 0) {
                          _showEditDialog(originalIdx, sortedRows[i]);
                        }
                      },
                      onDelete: (i) async {
                        final originalIdx = rows.indexOf(sortedRows[i]);
                        if (originalIdx >= 0) {
                          ref.read(resultProvider.notifier).removeRow(originalIdx);
                          await ref.read(resultProvider.notifier).saveToFile();
                        }
                      },
                    ),

                    // 添加节点输入框
                    if (_editMode) ...[
                      const SizedBox(height: 16),
                      card(
                        context,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addNodeCtrl,
                                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'ip:port#CC source（如 1.2.3.4:443#US mia）',
                                  hintStyle: TextStyle(color: t.textDim, fontSize: 14),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  border: OutlineInputBorder(borderRadius: t.radius),
                                ),
                                onSubmitted: (_) => _addNode(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filled(
                              icon: const Icon(Icons.add),
                              tooltip: '添加节点',
                              onPressed: _addNode,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _addNode() {
    final text = _addNodeCtrl.text.trim();
    if (text.isEmpty) return;
    ref.read(resultProvider.notifier).addRow(text);
    _addNodeCtrl.clear();
    ref.read(resultProvider.notifier).saveToFile();
  }

  Widget _pushGithubButton(BuildContext context, String file) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.edgeOrange,
        side: BorderSide(color: AppTheme.edgeOrange),
      ),
      onPressed: _pushing
          ? null
          : () async {
              setState(() => _pushing = true);
              try {
                final (ok, code, msg) =
                    await ref.read(subProvider.notifier).pushFile(file);
                if (!mounted) return;
                AppToast.show(context, msg, success: ok);
              } finally {
                if (mounted) setState(() => _pushing = false);
              }
            },
      icon: _pushing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.cloud_upload),
      label: Text(_pushing ? '推送中…' : '推送 GitHub', style: const TextStyle(fontSize: 14)),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 国家分布小卡片
// ═══════════════════════════════════════════════════════

class _GeoChip extends StatelessWidget {
  final String code;
  final int count;
  const _GeoChip({required this.code, required this.count});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final flag = countryCodeToFlag(code);
    final name = countryCodeToName(code);
    final display = code == '未知' ? '未知' : '$flag $name';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(display, style: TextStyle(fontSize: 14, color: t.text, fontFamily: 'AppMono')),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.edgeOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 统计区
// ═══════════════════════════════════════════════════════

class ResultStatsRow extends StatelessWidget {
  const ResultStatsRow({
    super.key,
    required this.rows,
    required this.geo,
    required this.lowestLatency,
  });

  final List<ResultRow> rows;
  final Map<String, int> geo;
  final double? lowestLatency;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _stat(context, '节点数', rows.length.toDouble(), Icons.storage, decimals: 0),
        _stat(context, '国家/地区', geo.length.toDouble(), Icons.public, decimals: 0),
        _stat(context, '最低延迟', lowestLatency ?? 0, Icons.timeline, decimals: 0, suffix: ' ms'),
      ],
    );
  }

  Widget _stat(BuildContext context, String title, num value, IconData icon, {int decimals = 0, String? suffix}) {
    final t = AppThemeExt.of(context);
    return SizedBox(
      width: 200,
      child: card(
        context,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.edgeOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.edgeOrange, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: t.textDim)),
                  const SizedBox(height: 3),
                  CountUpText(
                    value,
                    decimals: decimals,
                    suffix: suffix,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 结果表格
// ═══════════════════════════════════════════════════════

class ResultTable extends StatelessWidget {
  const ResultTable({
    super.key,
    required this.rows,
    this.editMode = false,
    this.onDelete,
    this.onEdit,
    this.sortCol = 1,
    this.sortAsc = true,
    this.onSort,
  });

  final List<ResultRow> rows;
  final bool editMode;
  final void Function(int index)? onDelete;
  final void Function(int index)? onEdit;
  final int sortCol;
  final bool sortAsc;
  final void Function(int col)? onSort;

  @override
  Widget build(BuildContext context) {
    double maxLatency = 0;
    for (final r in rows) {
      final v = parseLatency(r.latency);
      if (v != null && v > maxLatency) maxLatency = v;
    }

    final colWidths = editMode
        ? [FlexColumnWidth(4), FlexColumnWidth(2), FlexColumnWidth(1.5), FlexColumnWidth(2), IntrinsicColumnWidth()]
        : [FlexColumnWidth(4), FlexColumnWidth(2), FlexColumnWidth(1.5), FlexColumnWidth(2)];

    return card(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _headerRow(context, colWidths),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: ListView.builder(
              itemCount: rows.length,
              itemExtent: kIsMobile ? 64 : 60,
              itemBuilder: (context, i) {
                final row = rows[i];
                return _dataRow(context, i, row, maxLatency, colWidths);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context, List<TableColumnWidth> colWidths) {
    final t = AppThemeExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHover,
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Table(
        columnWidths: {for (var i = 0; i < colWidths.length; i++) i: colWidths[i]},
        children: [
          TableRow(
            children: [
              _sortHeader(context, '节点', 0),
              _sortHeader(context, '延迟', 1),
              _sortHeader(context, '国家', 2),
              _sortHeader(context, '来源', 3),
              if (editMode) _th(context, ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, int index, ResultRow row, double maxLatency, List<TableColumnWidth> colWidths) {
    return _DataRowWidget(
      index: index,
      row: row,
      maxLatency: maxLatency,
      colWidths: colWidths,
      editMode: editMode,
      onEdit: onEdit != null ? () => onEdit!.call(index) : null,
      onDelete: onDelete != null ? () => onDelete!.call(index) : null,
    );
  }

  Widget _sortHeader(BuildContext context, String label, int col) {
    final t = AppThemeExt.of(context);
    final isActive = sortCol == col;
    return InkWell(
      onTap: () => onSort?.call(col),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isActive ? t.text : t.textDim)),
            if (isActive) ...[
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: sortAsc ? 0 : 0.5,
                duration: Motion.durFast,
                child: Icon(Icons.arrow_drop_up, size: 18, color: AppTheme.edgeOrange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _th(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: t.textDim)));
  }

  static Widget _td(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(s, style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14)));
  }

  static Widget _nodeCell(BuildContext context, String ipPort) {
    final t = AppThemeExt.of(context);
    final lastColon = ipPort.lastIndexOf(':');
    final rawHost = lastColon > 0 ? ipPort.substring(0, lastColon) : ipPort;
    final port = lastColon > 0 ? ipPort.substring(lastColon) : '';
    final host = rawHost;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: RichText(
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        text: TextSpan(
          style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14),
          children: [
            TextSpan(text: host),
            if (port.isNotEmpty)
              TextSpan(text: port, style: TextStyle(color: t.textDim)),
          ],
        ),
      ),
    );
  }

  static Widget _latencyCell(BuildContext context, String? latency, double maxLatency) {
    final t = AppThemeExt.of(context);
    final value = parseLatency(latency);
    final display = latency ?? '—';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(display, style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14)),
          if (value != null && maxLatency > 0) ...[
            const SizedBox(height: 5),
            _LatencyBar(value: value, maxLatency: maxLatency),
          ],
        ],
      ),
    );
  }

  static Widget _countryCell(BuildContext context, String countryName, String node) {
    final t = AppThemeExt.of(context);
    final cc = nodeCountry(node);
    final flag = countryCodeToFlag(cc);
    final display = countryName.isEmpty ? '—' : '$flag $countryName';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Text(display, style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14)),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 数据行
// ═══════════════════════════════════════════════════════

class _DataRowWidget extends StatefulWidget {
  final int index;
  final ResultRow row;
  final double maxLatency;
  final List<TableColumnWidth> colWidths;
  final bool editMode;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _DataRowWidget({
    required this.index,
    required this.row,
    required this.maxLatency,
    required this.colWidths,
    required this.editMode,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_DataRowWidget> createState() => _DataRowWidgetState();
}

class _DataRowWidgetState extends State<_DataRowWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final baseColor = widget.index.isOdd ? t.surfaceHover.withValues(alpha: 0.3) : Colors.transparent;
    final hoverColor = _hovered ? t.surfaceHover : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.editMode) {
            // 编辑模式下点击行 → 编辑对话框
            widget.onEdit?.call();
          } else {
            // 普通模式下点击行 → 复制
            Clipboard.setData(ClipboardData(text: widget.row.ipPort));
            if (context.mounted) {
              AppToast.show(context, '已复制 ${widget.row.ipPort}');
            }
          }
        },
        child: AnimatedContainer(
          duration: Motion.durFast,
          curve: Motion.curveStandard,
          decoration: BoxDecoration(
            color: hoverColor,
            boxShadow: _hovered
                ? [BoxShadow(color: t.border.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Table(
            columnWidths: {for (var i = 0; i < widget.colWidths.length; i++) i: widget.colWidths[i]},
            children: [
              TableRow(children: [
                ResultTable._nodeCell(context, widget.row.ipPort),
                ResultTable._latencyCell(context, widget.row.latency, widget.maxLatency),
                ResultTable._countryCell(context, widget.row.country, widget.row.node),
                ResultTable._td(context, widget.row.source.isEmpty ? '—' : widget.row.source),
                if (widget.editMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: AppTheme.edgeOrange),
                          tooltip: '编辑',
                          onPressed: widget.onEdit,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(
                            minWidth: kIsMobile ? 48 : 32,
                            minHeight: kIsMobile ? 48 : 32,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: t.danger),
                          tooltip: '删除',
                          onPressed: widget.onDelete,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(
                            minWidth: kIsMobile ? 48 : 32,
                            minHeight: kIsMobile ? 48 : 32,
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 行内延迟条形图
// ═══════════════════════════════════════════════════════

class _LatencyBar extends StatelessWidget {
  final double value;
  final double maxLatency;
  const _LatencyBar({required this.value, required this.maxLatency});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final ratio = (value / maxLatency).clamp(0.0, 1.0);
    final color = t.latencyTierColor(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: ratio),
      duration: Motion.durSlow,
      curve: Motion.curveEmphasized,
      builder: (context, anim, _) {
        return CustomPaint(
          size: Size(double.infinity, 5),
          painter: _LatencyBarPainter(ratio: anim, color: color, bgColor: t.border),
        );
      },
    );
  }
}

class _LatencyBarPainter extends CustomPainter {
  final double ratio;
  final Color color;
  final Color bgColor;
  _LatencyBarPainter({required this.ratio, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(2.5));
    canvas.drawRRect(rrect, Paint()..color = bgColor);
    final fgWidth = size.width * ratio;
    if (fgWidth > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, fgWidth, size.height, const Radius.circular(2.5)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_LatencyBarPainter old) =>
      old.ratio != ratio || old.color != color;
}
