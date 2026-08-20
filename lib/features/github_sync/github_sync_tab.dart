import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/latency/latency_prober.dart';
import '../results/result_state.dart';
import '../results/results_table.dart';
import '../widgets/common.dart';
import 'github_sync_state.dart';

class GithubSyncTab extends ConsumerStatefulWidget {
  const GithubSyncTab({super.key});
  @override
  ConsumerState<GithubSyncTab> createState() => _GithubSyncTabState();
}

class _GithubSyncTabState extends ConsumerState<GithubSyncTab>
    with AutomaticKeepAliveClientMixin {
  bool _rawView = false;
  final _addNodeCtrl = TextEditingController();
  final _rawTextCtrl = TextEditingController();
  final _searchCtl = TextEditingController();

  int _sortCol = 1;
  bool _sortAsc = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _addNodeCtrl.dispose();
    _rawTextCtrl.dispose();
    super.dispose();
  }

  String _nodesToText(List<ResultRow> rows) {
    final sb = StringBuffer();
    for (final r in rows) {
      final parts = <String>[r.node];
      if (r.latency != null) parts.add(r.latency!);
      sb.writeln(parts.join(' '));
    }
    return sb.toString();
  }

  void _toggleRawView(bool toRaw) {
    if (toRaw) {
      final rows = ref.read(githubSyncProvider).remoteNodes;
      _rawTextCtrl.text = _nodesToText(rows);
    } else {
      ref.read(githubSyncProvider.notifier).setNodesFromText(_rawTextCtrl.text);
    }
    setState(() => _rawView = toRaw);
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

  void _showEditDialog(int originalIndex, ResultRow row) {
    final ipPortCtl = TextEditingController(text: row.ipPort);
    final sourceCtl = TextEditingController(text: row.source);
    final latencyCtl = TextEditingController(text: row.latency ?? '');

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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sourceCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: '来源',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latencyCtl,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: '延迟（如 50.00 ms）',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  final cc = nodeCountry(row.node);
                  final ccPart = cc.isNotEmpty ? '#$cc' : '';
                  final srcPart = source.isNotEmpty ? ' $source' : '';
                  final newNode = '$ipPort$ccPart$srcPart';
                  ref.read(githubSyncProvider.notifier).updateRemoteNode(
                      originalIndex, newNode,
                      latency: latency.isNotEmpty ? latency : null);
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
    final syncState = ref.watch(githubSyncProvider);

    ref.listen<GithubSyncState>(githubSyncProvider, (prev, next) {
      if (next.message != null && next.message != prev?.message) {
        AppToast.show(context, next.message!, success: true);
      }
      if (next.error != null && next.error != prev?.error) {
        AppToast.show(context, next.error!, success: false);
      }
      // 搜索关键词变化时同步 TextField
      if (next.searchQuery.isEmpty && _searchCtl.text.isNotEmpty) {
        _searchCtl.clear();
        setState(() {});
      }
    });

    final rows = syncState.remoteNodes;
    final sortedRows = _sortRows(rows);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW =
            constraints.maxWidth > 1100 ? 1080.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 标题行：标题 + 信息 pills ──
                  Row(
                    children: [
                      Text('GitHub 同步',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              )),
                      if (syncState.remoteFile != null) ...[
                        const SizedBox(width: 10),
                        pill(context, syncState.remoteFile!, t.surfaceHover),
                      ],
                      if (rows.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        pill(context, '${rows.length} IP', t.surfaceHover),
                      ],
                      if (syncState.searchQuery.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          '${syncState.filteredRemoteNodes.length}/${rows.length}',
                          style: TextStyle(color: AppTheme.edgeOrange, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── 操作行：视图切换 + 按钮 ──
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 拉取
                      FilledButton.icon(
                        onPressed: syncState.loading
                            ? null
                            : () => ref
                                .read(githubSyncProvider.notifier)
                                .pullFromGithub(),
                        icon: syncState.loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_download, size: 18),
                        label: Text(syncState.loading ? '拉取中…' : '拉取',
                            style: const TextStyle(fontSize: 13)),
                      ),
                      // 推送
                      if (rows.isNotEmpty)
                        _pushGithubButton(context),
                      if (rows.isNotEmpty) ...[
                        // 视图切换
                        ToggleButtons(
                          isSelected: [!_rawView, _rawView],
                          borderRadius: t.radius,
                          selectedColor: Colors.white,
                          fillColor: AppTheme.edgeOrange,
                          color: t.textDim,
                          onPressed: (i) => _toggleRawView(i == 1),
                          constraints: const BoxConstraints(minHeight: 34, minWidth: 60),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('解析', style: TextStyle(fontSize: 13))),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('原始', style: TextStyle(fontSize: 13))),
                          ],
                        ),
                        // 编辑
                        IconButton.filledTonal(
                          icon: Icon(ref.watch(editModeProvider) ? Icons.edit_off : Icons.edit, size: 18),
                          tooltip: ref.watch(editModeProvider) ? '退出编辑' : '编辑',
                          iconSize: 18,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              ref.read(editModeProvider.notifier).state = !ref.read(editModeProvider),
                        ),
                        // 去重
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.edgeOrange,
                            side: BorderSide(color: AppTheme.edgeOrange),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => ref
                              .read(githubSyncProvider.notifier)
                              .deduplicateNodes(),
                          icon: const Icon(Icons.filter_alt_off, size: 16),
                          label: const Text('去重', style: TextStyle(fontSize: 13)),
                        ),
                        // 搜索框
                        if (rows.isNotEmpty && !_rawView)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 200,
                              child: TextField(
                                controller: _searchCtl,
                                style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: '搜索 IP / 注释…',
                                  hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                                  prefixIcon: const Icon(Icons.search, size: 18),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: t.radius),
                                  suffixIcon: _searchCtl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () {
                                            _searchCtl.clear();
                                            setState(() {});
                                            ref.read(githubSyncProvider.notifier).setSearchQuery('');
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (v) {
                                  setState(() {});
                                  ref.read(githubSyncProvider.notifier).setSearchQuery(v);
                                },
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 空状态 ──
                  if (rows.isEmpty && !syncState.loading)
                    _emptyState(context, t, syncState.error),

                  // ── 原始内容视图 ──
                  if (_rawView && rows.isNotEmpty) ...[
                    card(
                      context,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.content_paste, size: 16, color: t.textDim),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text('粘贴大量 IP 后点「粘贴并去重」追加合并',
                                    style: TextStyle(color: t.textDim, fontSize: 13)),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.content_paste_go, size: 16),
                                label: const Text('粘贴并去重', style: TextStyle(fontSize: 13)),
                                onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null && data!.text!.isNotEmpty) {
                                    _rawTextCtrl.text = data.text!;
                                    ref.read(githubSyncProvider.notifier).appendAndDedup(data.text!);
                                    setState(() => _rawView = false);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.5,
                              minHeight: 200,
                            ),
                            child: TextField(
                              controller: _rawTextCtrl,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(fontFamily: 'AppMono', fontSize: 13, height: 1.5),
                              decoration: InputDecoration(
                                hintText: '每行一个节点，如：\n1.2.3.4:443#US CM 50.00ms\n5.6.7.8:2053#HK edgetunnel',
                                hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                                isDense: true,
                                contentPadding: const EdgeInsets.all(12),
                                border: OutlineInputBorder(borderRadius: t.radius),
                                filled: true,
                                fillColor: t.bg,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── 节点表格 ──
                  if (rows.isNotEmpty && !_rawView)
                    ResultTable(
                      rows: sortedRows,
                      editMode: ref.watch(editModeProvider),
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
                          ref
                              .read(githubSyncProvider.notifier)
                              .removeRemoteNode(originalIdx);
                        }
                      },
                    ),

                  // ── 添加节点输入框 ──
                  if (ref.watch(editModeProvider) && rows.isNotEmpty && !_rawView) ...[
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
                                  fontFamily: 'AppMono', fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'ip:port#CC source',
                                hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: t.radius),
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
    ref.read(githubSyncProvider.notifier).addRemoteNode(text);
    _addNodeCtrl.clear();
  }

  Widget _emptyState(BuildContext context, AppThemeExt t, String? error) {
    return Container(
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
            child: Icon(Icons.cloud_sync_outlined,
                size: 36,
                color: AppTheme.edgeOrange.withValues(alpha: 0.6)),
          )
              .animate(delay: 0.ms)
              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
              .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
                  duration: Motion.staggerDur, curve: Motion.curveStandard),
          const SizedBox(height: 20),
          Text(error ?? '点击「拉取」获取远程结果文件',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: error != null ? t.danger : t.text))
              .animate(delay: 80.ms)
              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
              .slideY(begin: 0.2, end: 0,
                  duration: Motion.staggerDur, curve: Motion.curveStandard),
          const SizedBox(height: 10),
          Text(
              error != null
                  ? '请检查 Token/Repo/Branch 配置是否正确'
                  : '拉取后可编辑、去重、再推送到 GitHub',
              style: TextStyle(color: t.textDim, fontSize: 14))
              .animate(delay: 160.ms)
              .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
              .slideY(begin: 0.2, end: 0,
                  duration: Motion.staggerDur, curve: Motion.curveStandard),
        ],
      ),
    );
  }

  Widget _pushGithubButton(BuildContext context) {
    final syncState = ref.watch(githubSyncProvider);
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.edgeOrange,
        foregroundColor: Colors.white,
      ),
      onPressed: syncState.pushing
          ? null
          : () async {
              await ref.read(githubSyncProvider.notifier).pushToGithub();
            },
      icon: syncState.pushing
          ? const SizedBox(
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.cloud_upload, size: 18),
      label: Text(syncState.pushing ? '推送中…' : '推送',
          style: const TextStyle(fontSize: 13)),
    );
  }
}
