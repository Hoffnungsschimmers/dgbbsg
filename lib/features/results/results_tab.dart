import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/export/result_exporter.dart';
import '../../core/net/endpoint.dart';
import '../../core/net/landing_history.dart';
import '../../core/storage/result_files.dart';
import '../subscriptions/subscriptions_state.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';
import 'result_state.dart';
import 'results_table.dart';

class ResultsTab extends ConsumerStatefulWidget {
  const ResultsTab({super.key});
  @override
  ConsumerState<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends ConsumerState<ResultsTab>
    with AutomaticKeepAliveClientMixin {
  bool _rawView = false;
  bool _pushing = false;
  bool _restoring = false;
  final _addNodeCtrl = TextEditingController();
  final _rawTextCtrl = TextEditingController();
  final _searchCtl = TextEditingController();
  String _rawBaseline = '';

  bool get _draftChanged => _rawView && _rawTextCtrl.text != _rawBaseline;

  void _updateEditBusy() {
    final st = ref.read(resultProvider);
    ref.read(resultBusyProvider.notifier).state =
        _draftChanged ||
        st.saving ||
        (st.dirty && st.currentFile != null) ||
        _pushing ||
        _restoring;
  }

  Future<bool> _saveEdits() async {
    try {
      await ref.read(resultProvider.notifier).saveToFile();
      return true;
    } catch (e) {
      if (mounted) AppToast.show(context, '保存失败，修改仍保留在界面中：$e', success: false);
      return false;
    }
  }

  Future<void> _changeView(int index) async {
    final toRaw = index == 1;
    if (toRaw == _rawView) return;
    if (toRaw) {
      _rawBaseline = ref.read(resultProvider).toText();
      _rawTextCtrl.text = _rawBaseline;
    } else if (_draftChanged) {
      try {
        ref.read(resultProvider.notifier).applyRawText(_rawTextCtrl.text);
      } on FormatException catch (e) {
        AppToast.show(context, e.message, success: false);
        return;
      }
      if (!await _saveEdits() || !mounted) return;
    }
    if (mounted) {
      setState(() => _rawView = toRaw);
      _updateEditBusy();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_draftChanged && !ref.read(resultProvider).dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('放弃未保存的修改？'),
            content: const Text('当前编辑尚未保存，继续将重新加载结果。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃修改'),
              ),
            ],
          ),
        ) ==
        true;
  }

  int _sortCol = 0;
  bool _sortAsc = true;

  @override
  bool get wantKeepAlive => true;

  Future<void> _showSnapshots() async {
    if (_restoring || ref.read(subProvider).running) return;
    if (!await _confirmDiscard() || !mounted) return;
    try {
      final notifier = ref.read(resultProvider.notifier);
      final snapshots = await notifier.snapshots();
      if (!mounted) return;
      if (snapshots.isEmpty) {
        AppToast.show(context, '当前文件还没有本地快照');
        return;
      }
      final selected = await showDialog<io.File>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('恢复历史结果'),
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择快照；恢复前会备份当前结果。'),
            ),
            for (final file in snapshots)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, file),
                child: Text(file.uri.pathSegments.last),
              ),
          ],
        ),
      );
      if (selected == null || !mounted || ref.read(subProvider).running) return;
      setState(() => _restoring = true);
      ref.read(resultBusyProvider.notifier).state = true;
      await notifier.restoreSnapshot(selected);
      if (!mounted) return;
      setState(() => _rawView = false);
      AppToast.show(context, '历史结果已恢复；恢复前的结果已备份');
    } catch (e) {
      if (mounted) AppToast.show(context, '恢复失败：$e', success: false);
    } finally {
      if (mounted && _restoring)
        ref.read(resultBusyProvider.notifier).state = false;
      if (mounted) setState(() => _restoring = false);
      if (mounted) _updateEditBusy();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _addNodeCtrl.dispose();
    _rawTextCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 配置就绪后自动加载默认结果文件（configProvider 是 FutureProvider，
    // 首次 build 时 .value 必为 null，不能在此同步读取）。
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg != null && ref.read(resultProvider).rows.isEmpty) {
      ref.read(resultProvider.notifier).refreshFile(cfg.subOutputFile);
    }
    ref.listenManual(configProvider, (prev, next) {
      final v = next.valueOrNull;
      if (prev?.valueOrNull == null &&
          v != null &&
          ref.read(resultProvider).rows.isEmpty) {
        ref.read(resultProvider.notifier).refreshFile(v.subOutputFile);
      }
    });
    ref.listenManual(resultProvider, (prev, next) {
      _updateEditBusy();
      if (prev != null &&
          prev.searchQuery != next.searchQuery &&
          next.searchQuery.isEmpty &&
          _searchCtl.text.isNotEmpty) {
        _searchCtl.clear();
      }
    });
  }

  /// 右上角 IP 数量小框（圆角方框，青绿渐变，与表格区样式区分）。
  Widget _ipCountBox(BuildContext context, int count) {
    final t = AppThemeExt.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: t.accentGradient(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_outlined, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: 'AppMono',
            ),
          ),
          const SizedBox(width: 2),
          const Text(
            'IP',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
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
          cmp = a.annotation.compareTo(b.annotation);
          break;
        default:
          cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  /// 打开落地历史面板（IP → 历次落地变化）。
  Future<void> _showLandingHistory() async {
    final history = await ref.read(landingHistoryProvider.future);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _LandingHistoryDialog(history: history),
    );
  }

  void _showEditDialog(int originalIndex, ResultRow row) {
    final ipPortCtl = TextEditingController(text: row.ipPort);
    final sourceCtl = TextEditingController(text: row.source);

    showDialog<void>(
      context: context,
      builder: (ctx) {
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sourceCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: '来源',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                if (ipPort.isNotEmpty) {
                  final cc = nodeCountry(row.node);
                  final ccPart = cc.isNotEmpty ? '#$cc' : '';
                  final srcPart = source.isNotEmpty ? ' $source' : '';
                  final newNode = '$ipPort$ccPart$srcPart';
                  if (!validResultNode(newNode)) {
                    AppToast.show(ctx, '请输入有效的地址:端口', success: false);
                    return;
                  }
                  try {
                    ref
                        .read(resultProvider.notifier)
                        .updateRow(originalIndex, newNode);
                  } on FormatException catch (e) {
                    AppToast.show(ctx, e.message, success: false);
                    return;
                  }
                  _saveEdits();
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
    final editMode = ref.watch(editModeProvider);
    final cfg = cfgAsync.value;

    final rows = state.rows;
    final filteredRows = state.filteredRows;
    // Editing uses file order so dragging has the same visible and saved order.
    final sortedRows = editMode ? filteredRows : _sortRows(filteredRows);

    return AbsorbPointer(
      absorbing:
          ref.watch(subProvider).running ||
          ref.watch(webDavBusyProvider) ||
          _pushing ||
          _restoring ||
          state.saving,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final maxW = constraints.maxWidth > 1100
              ? 1080.0
              : constraints.maxWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 标题行：标题 + 来源/时间 pills；IP 数量放右上角（窄屏自动换行）──
                    LayoutBuilder(
                      builder: (ctx, c) {
                        final narrow = MediaQuery.sizeOf(context).width < 600;
                        if (narrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '订阅结果',
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (rows.isNotEmpty)
                                    _ipCountBox(context, rows.length),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (state.sourceLabel != null)
                                    pill(
                                      context,
                                      state.sourceLabel!,
                                      t.surfaceHover,
                                    ),
                                  if (state.generatedAt != null)
                                    pillWithIcon(
                                      context,
                                      icon: Icons.schedule,
                                      text: state.generatedAt!,
                                      bg: t.surfaceHover,
                                    ),
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Text(
                              '订阅结果',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                            ),
                            if (state.sourceLabel != null) ...[
                              const SizedBox(width: 10),
                              pill(context, state.sourceLabel!, t.surfaceHover),
                            ],
                            if (state.generatedAt != null) ...[
                              const SizedBox(width: 10),
                              pillWithIcon(
                                context,
                                icon: Icons.schedule,
                                text: state.generatedAt!,
                                bg: t.surfaceHover,
                              ),
                            ],
                            const Spacer(),
                            if (rows.isNotEmpty)
                              _ipCountBox(context, rows.length),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // ── 操作行：搜索 + 视图切换 + 按钮 ──
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 搜索框
                        if (rows.isNotEmpty && !_rawView)
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _searchCtl,
                              style: const TextStyle(
                                fontFamily: 'AppMono',
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText: '搜索 IP / 注释…',
                                hintStyle: TextStyle(
                                  color: t.textDim,
                                  fontSize: 13,
                                ),
                                prefixIcon: const Icon(Icons.search, size: 18),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: t.radius,
                                ),
                                suffixIcon: _searchCtl.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _searchCtl.clear();
                                          setState(() {});
                                          ref
                                              .read(resultProvider.notifier)
                                              .setSearchQuery('');
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (v) {
                                setState(() {});
                                ref
                                    .read(resultProvider.notifier)
                                    .setSearchQuery(v);
                              },
                            ),
                          ),
                        if (rows.isNotEmpty &&
                            !_rawView &&
                            filteredRows.length != rows.length)
                          Text(
                            '${filteredRows.length}/${rows.length}',
                            style: const TextStyle(
                              color: AppTheme.edgeOrange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        // 刷新
                        if (rows.isNotEmpty || _rawView)
                          IconButton.filledTonal(
                            icon: const Icon(Icons.refresh, size: 18),
                            tooltip: '刷新',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              if (!await _confirmDiscard() || !mounted) return;
                              try {
                                await ref
                                    .read(resultProvider.notifier)
                                    .refreshFile(cfg?.subOutputFile ?? '');
                                if (mounted) setState(() => _rawView = false);
                                if (mounted) _updateEditBusy();
                              } catch (e) {
                                if (mounted)
                                  AppToast.show(
                                    context,
                                    '刷新失败：$e',
                                    success: false,
                                  );
                              }
                            },
                          ),
                        // 落地历史
                        if (state.currentFile != null)
                          IconButton.filledTonal(
                            icon: const Icon(Icons.restore, size: 18),
                            tooltip: '恢复历史结果',
                            visualDensity: VisualDensity.compact,
                            onPressed:
                                _restoring || ref.watch(subProvider).running
                                ? null
                                : _showSnapshots,
                          ),
                        if (rows.isNotEmpty && !_rawView)
                          IconButton.filledTonal(
                            icon: const Icon(Icons.history, size: 18),
                            tooltip: '落地历史（各 IP 历次实测落地）',
                            visualDensity: VisualDensity.compact,
                            onPressed: _showLandingHistory,
                          ),
                        if (rows.isNotEmpty) ...[
                          // 视图切换
                          ToggleButtons(
                            isSelected: [!_rawView, _rawView],
                            borderRadius: t.radius,
                            selectedColor: Colors.white,
                            fillColor: AppTheme.edgeOrange,
                            color: t.textDim,
                            onPressed: _changeView,
                            constraints: const BoxConstraints(
                              minHeight: 34,
                              minWidth: 60,
                            ),
                            children: const [
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '解析',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  '原始',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          // 编辑（切换可编辑模式）
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: editMode ? t.accent : t.textDim,
                              side: BorderSide(
                                color: editMode ? t.accent : t.border,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                ref.read(editModeProvider.notifier).state =
                                    !editMode,
                            icon: Icon(
                              editMode ? Icons.check : Icons.edit,
                              size: 16,
                            ),
                            label: Text(
                              editMode ? '完成' : '编辑',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          // 导出
                          _exportButton(context, rows),
                        ],
                        if (!_rawView) ...[
                          IconButton.filledTonal(
                            tooltip: '撤销',
                            icon: const Icon(Icons.undo, size: 18),
                            onPressed: state.canUndo
                                ? () {
                                    ref.read(resultProvider.notifier).undo();
                                    _saveEdits();
                                  }
                                : null,
                          ),
                          IconButton.filledTonal(
                            tooltip: '重做',
                            icon: const Icon(Icons.redo, size: 18),
                            onPressed: state.canRedo
                                ? () {
                                    ref.read(resultProvider.notifier).redo();
                                    _saveEdits();
                                  }
                                : null,
                          ),
                        ],
                        if (state.currentFile != null)
                          Text(
                            state.saving
                                ? '正在保存…'
                                : state.saveError != null
                                ? '保存失败'
                                : state.dirty
                                ? '尚未保存'
                                : '已保存',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.saveError != null
                                  ? t.danger
                                  : t.textDim,
                            ),
                          ),
                        if (state.dirty && state.currentFile != null)
                          TextButton(
                            onPressed: _saveEdits,
                            child: const Text('重试保存'),
                          ),
                        // 推送 GitHub
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textDim,
                            side: BorderSide(color: t.border),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed:
                              _pushing ||
                                  _restoring ||
                                  ref.watch(subProvider).running
                              ? null
                              : _pushToGithub,
                          icon: _pushing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload, size: 16),
                          label: const Text(
                            '推送 GitHub',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        // 地址（复制 raw 地址）
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: t.textDim,
                            side: BorderSide(color: t.border),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _showAddressPicker,
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text(
                            '复制地址',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 空状态 ──
                    if (rows.isEmpty && !_rawView)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 64,
                          horizontal: 32,
                        ),
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
                                    color: AppTheme.edgeOrange.withValues(
                                      alpha: 0.08,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.inbox_outlined,
                                    size: 36,
                                    color: AppTheme.edgeOrange.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                )
                                .animate(delay: 0.ms)
                                .fadeIn(
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                )
                                .scale(
                                  begin: const Offset(0.8, 0.8),
                                  end: const Offset(1, 1),
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                ),
                            const SizedBox(height: 20),
                            Text(
                                  '暂无结果',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: t.text,
                                  ),
                                )
                                .animate(delay: 80.ms)
                                .fadeIn(
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                )
                                .slideY(
                                  begin: 0.2,
                                  end: 0,
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                ),
                            const SizedBox(height: 10),
                            Text(
                                  '运行「获取订阅」后，结果会显示在这里。',
                                  style: TextStyle(
                                    color: t.textDim,
                                    fontSize: 14,
                                  ),
                                )
                                .animate(delay: 160.ms)
                                .fadeIn(
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                )
                                .slideY(
                                  begin: 0.2,
                                  end: 0,
                                  duration: Motion.staggerDur,
                                  curve: Motion.curveStandard,
                                ),
                          ],
                        ),
                      )
                    // ── 原始内容视图（可编辑）──
                    else if (_rawView)
                      card(
                        context,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.edit_note,
                                  size: 16,
                                  color: t.textDim,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '编辑原始内容（修改后切回解析视图自动保存）',
                                    style: TextStyle(
                                      color: t.textDim,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text(
                                    '全部复制',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  onPressed: _rawTextCtrl.text.isEmpty
                                      ? null
                                      : () {
                                          Clipboard.setData(
                                            ClipboardData(
                                              text: _rawTextCtrl.text,
                                            ),
                                          );
                                          AppToast.show(context, '已复制全部内容');
                                        },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.5,
                                minHeight: 200,
                              ),
                              child: TextField(
                                controller: _rawTextCtrl,
                                onChanged: (_) {
                                  setState(() {});
                                  _updateEditBusy();
                                },
                                maxLines: null,
                                expands: true,
                                style: const TextStyle(
                                  fontFamily: 'AppMono',
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText:
                                      '每行一个节点，如：\n1.2.3.4:443#精品v4 1\n[2606:4700:52::1]:443#精品v6 1',
                                  hintStyle: TextStyle(
                                    color: t.textDim.withValues(alpha: 0.5),
                                    fontSize: 13,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(12),
                                  border: OutlineInputBorder(
                                    borderRadius: t.radius,
                                  ),
                                  filled: true,
                                  fillColor: t.surface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    // ── 解析视图 ──
                    else ...[
                      // 数据表格
                      ResultTable(
                        rows: sortedRows,
                        editMode: editMode,
                        sortCol: _sortCol,
                        sortAsc: _sortAsc,
                        onReorder: editMode && state.searchQuery.isEmpty
                            ? (oldIndex, newIndex) async {
                                final originalOld = rows.indexOf(
                                  sortedRows[oldIndex],
                                );
                                final originalNew =
                                    newIndex >= sortedRows.length
                                    ? rows.length
                                    : rows.indexOf(sortedRows[newIndex]);
                                ref
                                    .read(resultProvider.notifier)
                                    .reorderRow(originalOld, originalNew);
                                await _saveEdits();
                              }
                            : null,
                        onSort: editMode
                            ? null
                            : (col) {
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
                          _showEditDialog(
                            rows.indexOf(sortedRows[i]),
                            sortedRows[i],
                          );
                        },
                        onDelete: (i) async {
                          ref
                              .read(resultProvider.notifier)
                              .removeRow(rows.indexOf(sortedRows[i]));
                          await _saveEdits();
                        },
                      ),

                      // 添加节点输入框
                      if (editMode) ...[
                        const SizedBox(height: 12),
                        card(
                          context,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _addNodeCtrl,
                                  style: const TextStyle(
                                    fontFamily: 'AppMono',
                                    fontSize: 13,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'ip:port#CC 来源 备注',
                                    hintStyle: TextStyle(
                                      color: t.textDim,
                                      fontSize: 13,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: t.radius,
                                    ),
                                  ),
                                  onSubmitted: (_) => _addNode(),
                                ),
                              ),
                              const SizedBox(width: 8),
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
      ),
    );
  }

  void _addNode() {
    final text = _addNodeCtrl.text.trim();
    if (text.isEmpty) return;
    if (!validResultNode(text)) {
      AppToast.show(context, '请输入有效的地址:端口', success: false);
      return;
    }
    try {
      ref.read(resultProvider.notifier).addRow(text);
    } on FormatException catch (e) {
      AppToast.show(context, e.message, success: false);
      return;
    }
    _addNodeCtrl.clear();
    _saveEdits();
  }

  Widget _exportButton(BuildContext context, List<ResultRow> rows) {
    final t = AppThemeExt.of(context);
    return PopupMenuButton<ExportFormat>(
      tooltip: '导出',
      enabled: rows.isNotEmpty,
      onSelected: (format) => _doExport(context, rows, format),
      itemBuilder: (_) => [
        for (final format in ExportFormat.values)
          PopupMenuItem(
            value: format,
            child: Row(
              children: [
                Icon(format.icon, size: 16, color: AppTheme.edgeOrange),
                const SizedBox(width: 8),
                Text(format.label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textDim,
          side: BorderSide(color: t.border),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: null,
        icon: const Icon(Icons.download, size: 16),
        label: const Text('导出', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  Future<void> _doExport(
    BuildContext context,
    List<ResultRow> rows,
    ExportFormat format,
  ) async {
    if (_draftChanged) {
      AppToast.show(context, '请先切回解析视图，应用原始内容的修改', success: false);
      return;
    }
    if (format.isTemplate) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出配置模板'),
          content: const Text(
            '当前结果只保留地址与备注，缺少真实协议、密码、UUID 和 TLS 参数。模板含占位值，需要手动补齐，不能直接作为可用订阅。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导出模板'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }
    final dir = (await getApplicationDocumentsDirectory()).path;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = switch (format) {
      ExportFormat.csv => 'csv',
      ExportFormat.clashYaml => 'yaml',
      ExportFormat.v2rayJson => 'v2ray.json',
      ExportFormat.singboxJson => 'singbox.json',
      ExportFormat.plain => 'txt',
    };
    final path = '$dir/export_$ts.$ext';
    final content = ResultExporter.export(rows, format);

    await Clipboard.setData(ClipboardData(text: content));
    await io.File(path).writeAsString(content);
    if (!context.mounted) return;
    AppToast.show(context, '已导出 ${format.label}（已复制到剪贴板 + 保存到文件）');
  }

  /// 推送当前结果到 GitHub（仓库根目录，分支取配置）。
  Future<void> _pushToGithub() async {
    if (_pushing) return;
    if (_draftChanged) {
      AppToast.show(context, '请先切回解析视图，应用原始内容的修改', success: false);
      return;
    }
    if (ref.read(resultProvider).dirty && !await _saveEdits()) return;
    if (!mounted) return;
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null || cfg.githubToken.trim().isEmpty) {
      AppToast.show(context, '请先在配置页填写 GitHub Token', success: false);
      return;
    }
    final st = ref.read(resultProvider);
    if (st.rows.isEmpty) {
      AppToast.show(context, '当前结果为空，无法推送', success: false);
      return;
    }
    final issue = st.qualityIssue(cfg);
    if (issue != null) {
      AppToast.show(context, '推送保护：$issue', success: false);
      return;
    }
    final fileName = (st.currentFile ?? cfg.subOutputFile)
        .split(RegExp(r'[\\/]'))
        .last;
    setState(() => _pushing = true);
    ref.read(resultBusyProvider.notifier).state = true;
    try {
      final pusher = ref.read(githubPushProvider)(cfg);
      await pusher.pushFile(
        fileName,
        st.toText(),
        message: 'push from cfnb (${st.rows.length} nodes)',
      );
      if (st.currentFile != null) {
        final dir = await getApplicationDocumentsDirectory();
        final local = io.File(resolveOutputPath(st.currentFile!, dir.path));
        try {
          await markResultPushed(local, st.toText());
          await ref.read(resultProvider.notifier).loadFile(st.currentFile!);
        } catch (e) {
          ref.read(subLoggerProvider).warning('推送已成功，本地推送记录保存失败：$e');
        }
      }
      if (!mounted) return;
      AppToast.show(context, '推送成功：$fileName');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '推送失败：$e', success: false);
    } finally {
      if (mounted) ref.read(resultBusyProvider.notifier).state = false;
      if (mounted) setState(() => _pushing = false);
      if (mounted) _updateEditBusy();
    }
  }

  /// 当前结果文件对应的 GitHub raw 地址及可直连镜像地址选项。
  /// 返回 [(名称, 地址), ...]，第一个为源地址。
  List<(String, String)> buildAddressOptions(AppConfig cfg, String fileName) {
    final raw =
        'https://raw.githubusercontent.com/${cfg.githubRepo}/refs/heads/${cfg.githubBranch}/$fileName';
    return [
      ('源（GitHub Raw）', raw),
      (
        'jsDelivr CDN',
        'https://cdn.jsdelivr.net/gh/${cfg.githubRepo}@${cfg.githubBranch}/$fileName',
      ),
      ('ghfast.top 加速', 'https://ghfast.top/$raw'),
      ('moeyy 镜像', 'https://github.moeyy.xyz/$raw'),
      ('ghproxy.net 镜像', 'https://ghproxy.net/$raw'),
    ];
  }

  /// 弹出地址选择列表：复制当前结果文件对应的 GitHub raw 地址或镜像地址。
  void _showAddressPicker() {
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null) return;
    final st = ref.read(resultProvider);
    final fileName = (st.currentFile ?? cfg.subOutputFile)
        .split(RegExp(r'[\\/]'))
        .last;
    final options = buildAddressOptions(cfg, fileName);
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择要复制的地址'),
        children: [
          for (final (label, url) in options)
            SimpleDialogOption(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.pop(ctx);
                AppToast.show(context, '已复制：$label');
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    url,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 落地历史面板：按 IP 展开查看历次实测落地（时间 / 机场码或归属地 / 国家码 / 当时的出口）。
/// 用途：同一个 Cloudflare anycast IP 在不同网络下会落到不同 POP，这里留下的正是
/// 「哪一次测量、走哪个出口、得到什么落地」的对照记录。
class _LandingHistoryDialog extends StatefulWidget {
  const _LandingHistoryDialog({required this.history});

  final LandingHistory history;

  @override
  State<_LandingHistoryDialog> createState() => _LandingHistoryDialogState();
}

class _LandingHistoryDialogState extends State<_LandingHistoryDialog> {
  final _queryCtl = TextEditingController();

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final q = _queryCtl.text.trim().toLowerCase();
    final ips =
        widget.history.keys
            .where((ip) => q.isEmpty || ip.toLowerCase().contains(q))
            .toList()
          ..sort();
    final width = (MediaQuery.sizeOf(context).width * 0.86).clamp(280.0, 560.0);

    return AlertDialog(
      title: const Text('落地历史'),
      content: SizedBox(
        width: width,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _queryCtl,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索 IP…',
                hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(borderRadius: t.radius),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ips.isEmpty
                  ? Center(
                      child: Text(
                        widget.history.isEmpty
                            ? '还没有落地记录：先在运行页点「测落地」。'
                            : '没有匹配的 IP。',
                        style: TextStyle(color: t.textDim, fontSize: 13),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final ip in ips)
                          ExpansionTile(
                            dense: true,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              ip,
                              style: const TextStyle(
                                fontFamily: 'AppMono',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '当前 ${widget.history[ip]!.first.cc}'
                              ' · 记录了 ${widget.history[ip]!.length} 次变化',
                              style: TextStyle(fontSize: 11, color: t.textDim),
                            ),
                            children: [
                              for (final o in widget.history[ip]!)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  title: Text(
                                    '${o.at}   ${o.colo.isEmpty ? '归属地' : o.colo} → ${o.cc}',
                                    style: const TextStyle(
                                      fontFamily: 'AppMono',
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: o.egressIp.isEmpty
                                      ? null
                                      : Text(
                                          '出口 ${o.egressIp}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: t.textDim,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
