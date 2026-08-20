import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../subscriptions/subscriptions_state.dart';
import '../widgets/common.dart';
import 'result_state.dart';

enum SortCol { order, speed, latency, quality, country }

class ResultsPage extends ConsumerStatefulWidget {
  const ResultsPage({super.key});
  @override
  ConsumerState<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends ConsumerState<ResultsPage> {
  String? _selectedFile;
  bool _rawView = false;
  bool _pushing = false;
  SortCol _sortCol = SortCol.order;
  bool _sortAsc = true;

  double? _num(String? s) {
    if (s == null) return null;
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  List<ResultRow> _sorted(List<ResultRow> rows) {
    if (_sortCol == SortCol.order) return rows;
    final list = [...rows];
    list.sort((a, b) {
      int c;
      switch (_sortCol) {
        case SortCol.order:
          return 0;
        case SortCol.speed:
          c = (_num(a.speed) ?? -1).compareTo(_num(b.speed) ?? -1);
        case SortCol.latency:
          c = (_num(a.latency) ?? 1e9).compareTo(_num(b.latency) ?? 1e9);
        case SortCol.quality:
          c = (a.quality ?? -1).compareTo(b.quality ?? -1);
        case SortCol.country:
          c = a.country.compareTo(b.country);
      }
      return _sortAsc ? c : -c;
    });
    return list;
  }

  void _toggleSort(SortCol col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = true;
      }
    });
  }

  String _buildCsv(List<ResultRow> rows) {
    final sb = StringBuffer('排名,节点,带宽,延迟,质量,国家\n');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      sb.writeln('${i + 1},${r.node},${r.speed ?? ''},${r.latency ?? ''},'
          '${r.quality?.toStringAsFixed(3) ?? ''},${r.country}');
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final state = ref.watch(resultProvider);
    final cfgAsync = ref.watch(configProvider);

    final candidates = <String>[
      cfgAsync.value?.subOutputFile ?? 'addressesapi.txt',
      cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt',
    ].where((p) => p.isNotEmpty).toSet().where((p) => File(p).existsSync()).toList();

    _selectedFile ??= state.currentFile ?? (candidates.isNotEmpty ? candidates.first : null);
    final effectiveSelected =
        (_selectedFile != null && candidates.contains(_selectedFile)) ? _selectedFile! : candidates.first;

    final rows = _sorted(state.rows);
    final geo = <String, int>{};
    for (final r in rows) {
      final c = r.country.isEmpty ? '未知' : r.country;
      geo[c] = (geo[c] ?? 0) + 1;
    }

    final bestSpeed = _best(rows, (r) => _num(r.speed), max: true);
    final lowestLatency = _best(rows, (r) => _num(r.latency), max: false);
    double? bestQuality;
    for (final r in rows) {
      if (r.quality != null && (bestQuality == null || r.quality! > bestQuality)) {
        bestQuality = r.quality;
      }
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth > 1100 ? 1080.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('优选结果',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      if (state.sourceLabel != null)
                        pill(context, state.sourceLabel!, t.surfaceHover, t.textDim),
                      const SizedBox(width: 12),
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
                      const SizedBox(width: 12),
                      _pushGithubButton(context, cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (candidates.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: t.surface,
                            borderRadius: t.radius,
                            border: Border.all(color: t.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: effectiveSelected,
                              items: candidates
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c,
                                            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
                                      ))
                                  .toList(),
                              onChanged: (v) async {
                                if (v == null) return;
                                _selectedFile = v;
                                setState(() {});
                                await ref.read(resultProvider.notifier).loadRaw(v);
                              },
                            ),
                          ),
                        ),
                        ToggleButtons(
                          isSelected: [!_rawView, _rawView],
                          borderRadius: t.radius,
                          selectedColor: Colors.white,
                          fillColor: t.primary,
                          color: t.textDim,
                          onPressed: (i) => setState(() => _rawView = i == 1),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('解析视图')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('原始内容')),
                          ],
                        ),
                        if (!_rawView && rows.isNotEmpty)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.copy_all, size: 16),
                            label: const Text('复制 CSV'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _buildCsv(state.rows)));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制表格 CSV 到剪贴板'), duration: Duration(seconds: 2)),
                              );
                            },
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (rows.isEmpty && !_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(40),
                      child: emptyState(context,
                          icon: Icons.inbox_outlined,
                          title: '暂无结果',
                          hint: '回到「工作台」运行「顺序执行全部」，或先运行「订阅IP / 延迟优选」。'),
                    )
                  else if (_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        height: 420,
                        child: (state.rawText == null || state.currentFile != _selectedFile)
                            ? Center(child: Text('加载中…', style: TextStyle(color: t.textDim)))
                            : RawTextView(state.rawText!, copyTooltip: '复制文件内容'),
                      ),
                    )
                  else ...[
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        StatCard('节点数', '${rows.length}', Icons.storage),
                        StatCard('来源数', '${geo.length}', Icons.public,
                            color: t.info),
                        StatCard('最高带宽',
                            bestSpeed != null ? '${bestSpeed.toStringAsFixed(1)} Mbps' : '—',
                            Icons.speed, color: t.success),
                        StatCard('最低延迟',
                            lowestLatency != null ? '${lowestLatency.toStringAsFixed(0)} ms' : '—',
                            Icons.timeline, color: t.warning),
                        StatCard('最高质量分',
                            bestQuality != null ? bestQuality.toStringAsFixed(2) : '—',
                            Icons.stars, color: t.primary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (geo.length > 1)
                      card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('国家 / 地区分布',
                                style: TextStyle(color: t.textDim, fontSize: 12)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: geo.entries
                                  .map((e) => Chip(
                                        label: Text('${e.key}  ${e.value}'),
                                        backgroundColor: t.bg,
                                        side: BorderSide(color: t.border),
                                        labelStyle: TextStyle(color: t.text, fontSize: 12),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    card(
                      context,
                      padding: EdgeInsets.zero,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 620),
                          child: Table(
                            columnWidths: const {
                              0: FlexColumnWidth(0.7),
                              1: FlexColumnWidth(4),
                              2: FlexColumnWidth(2.2),
                              3: FlexColumnWidth(1.6),
                              4: FlexColumnWidth(1.2),
                              5: FlexColumnWidth(1.0),
                            },
                            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: BoxDecoration(color: t.surfaceHover),
                                children: [
                                  _sortHeader(context, SortCol.order, '#'),
                                  _sortHeader(context, SortCol.country, '国家'),
                                  _sortHeader(context, SortCol.speed, '带宽'),
                                  _sortHeader(context, SortCol.latency, '延迟'),
                                  _sortHeader(context, SortCol.quality, '质量'),
                                  const Padding(
                                      padding: EdgeInsets.all(12), child: SizedBox.shrink()),
                                ],
                              ),
                              for (var i = 0; i < rows.length; i++)
                                TableRow(
                                  decoration: i.isEven
                                      ? null
                                      : BoxDecoration(color: t.surfaceHover.withValues(alpha: 0.35)),
                                  children: [
                                    _td(context, '${i + 1}', mono: true),
                                    _td(context, rows[i].country.isEmpty ? '—' : rows[i].country),
                                    _speedCell(context, rows[i].speed, bestSpeed),
                                    _latencyCell(context, rows[i].latency),
                                    _td(context,
                                        rows[i].quality?.toStringAsFixed(3) ?? '—',
                                        mono: true,
                                        color: rows[i].quality != null ? t.primary : null),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(rows[i].node,
                                          style: TextStyle(
                                              fontFamily: 'Consolas',
                                              fontSize: 12.5,
                                              color: t.text)),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- 表格单元格 ----------

  Widget _sortHeader(BuildContext context, SortCol col, String label) {
    final t = AppThemeExt.of(context);
    final active = _sortCol == col;
    return InkWell(
      onTap: () => _toggleSort(col),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? t.primary : t.textDim)),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: t.primary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _td(BuildContext context, String s, {bool mono = false, Color? color}) {
    final t = AppThemeExt.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(s,
          style: TextStyle(
              fontSize: 12,
              color: color ?? t.text,
              fontFamily: mono ? 'Consolas' : null)),
    );
  }

  Widget _speedCell(BuildContext context, String? speed, double? best) {
    final t = AppThemeExt.of(context);
    final v = _num(speed);
    final ratio = best == null || v == null ? 0.0 : (v / best).clamp(0.03, 1.0);
    final color = switch (v ?? 0) {
      final x when x >= 100 => t.success,
      final x when x >= 30 => t.primary,
      final x when x > 0 => t.warning,
      _ => t.border,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: t.border.withValues(alpha: 0.45),
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 70,
            child: Text(speed ?? '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontFamily: 'Consolas', fontSize: 11.5, color: speed == null ? t.textDim : t.text)),
          ),
        ],
      ),
    );
  }

  Widget _latencyCell(BuildContext context, String? latency) {
    final t = AppThemeExt.of(context);
    final v = _num(latency);
    final color = switch (v ?? 1e9) {
      final x when x <= 120 => t.success,
      final x when x <= 250 => t.warning,
      final x when x < 1e9 => t.danger,
      _ => t.textDim,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(latency ?? '—',
          style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: color)),
    );
  }

  double? _best(List<ResultRow> rows, double? Function(ResultRow) pick, {required bool max}) {
    double? best;
    for (final r in rows) {
      final v = pick(r);
      if (v == null) continue;
      if (best == null || (max ? v > best : v < best)) best = v;
    }
    return best;
  }

  // ---------- 推送 ----------

  Widget _pushGithubButton(BuildContext context, String file) {
    final t = AppThemeExt.of(context);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.primary,
        side: BorderSide(color: t.primary),
      ),
      onPressed: _pushing
          ? null
          : () async {
              setState(() => _pushing = true);
              try {
                final (ok, code, msg) = await ref.read(subProvider.notifier).pushFile(file);
                if (!mounted) return;
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(msg),
                    backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                    duration: const Duration(seconds: 4),
                  ));
                }
              } finally {
                if (mounted) setState(() => _pushing = false);
              }
            },
      icon: _pushing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload),
      label: Text(_pushing ? '推送中…' : '推送 GitHub'),
    );
  }
}