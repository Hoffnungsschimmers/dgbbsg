import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});
  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> with AutomaticKeepAliveClientMixin {
  final _genCtl = <TextEditingController>[];
  final _urlCtl = <TextEditingController>[];
  final _hostCtl = TextEditingController();
  final _uuidCtl = TextEditingController();
  final _countryCtl = TextEditingController();
  final _latencyOutCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _repoCtl = TextEditingController();
  final _branchCtl = TextEditingController();

  Timer? _saveTimer;
  AppConfig? _pendingCfg;
  bool _isSyncing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ref.listenManual(configProvider, (_, next) {
      next.whenData((cfg) {
        _syncControllers(cfg);
        // 启动时初始化 latestConfigProvider，确保运行时读到正确配置。
        ref.read(latestConfigProvider.notifier).state ??= cfg;
      });
    });
  }

  @override
  void dispose() {
    for (final c in _genCtl) { c.dispose(); }
    for (final c in _urlCtl) { c.dispose(); }
    _hostCtl.dispose();
    _uuidCtl.dispose();
    _countryCtl.dispose();
    _latencyOutCtl.dispose();
    _tokenCtl.dispose();
    _repoCtl.dispose();
    _branchCtl.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  void _syncIf(TextEditingController ctl, String v) {
    if (ctl.text != v) ctl.text = v;
  }

  void _syncList(List<TextEditingController> ctl, List<String> values) {
    while (ctl.length < values.length) { ctl.add(TextEditingController()); }
    while (ctl.length > values.length) { ctl.removeLast().dispose(); }
    for (var i = 0; i < values.length; i++) {
      if (ctl[i].text != values[i]) ctl[i].text = values[i];
    }
  }

  void _syncControllers(AppConfig cfg) {
    _isSyncing = true;
    _syncList(_genCtl, cfg.subGenerators);
    _syncList(_urlCtl, cfg.subUrls);
    _syncIf(_hostCtl, cfg.subNodeHost);
    _syncIf(_uuidCtl, cfg.subNodeUuid);
    _syncIf(_countryCtl, cfg.subDefaultCountry);
    _syncIf(_tokenCtl, cfg.githubToken);
    _syncIf(_repoCtl, cfg.githubRepo);
    _syncIf(_branchCtl, cfg.githubBranch);
    _syncIf(_latencyOutCtl, cfg.subLatencyOutputFile);
    _isSyncing = false;
  }

  void _save(AppConfig cfg) {
    if (_isSyncing) return;
    _pendingCfg = cfg;

    // 立即同步更新：运行时从此处读取最新配置，不受防抖/磁盘延迟影响。
    ref.read(latestConfigProvider.notifier).state = cfg;

    // 校验提示（非阻塞）
    final errors = cfg.validate();
    if (errors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) AppToast.show(context, errors.first, success: false);
      });
    }

    // 防抖持久化到 SharedPreferences（仅控制磁盘写入频率）。
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () async {
      final c = _pendingCfg;
      if (c == null) return;
      _pendingCfg = null;
      final repo = await ref.read(configRepositoryProvider.future);
      await repo.save(c);
      ref.invalidate(configProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cfgAsync = ref.watch(configProvider);

    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (cfg) {
        if (_genCtl.isEmpty && cfg.subGenerators.isNotEmpty) {
          _syncControllers(cfg);
        }
        final validationErrors = cfg.validate();
        return Column(
          children: [
            if (validationErrors.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.orange.withValues(alpha: 0.12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '配置有 ${validationErrors.length} 项校验问题：${validationErrors.first}',
                        style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubscriptionInput(context, cfg),
                    const SizedBox(height: 12),
                    _buildFetchSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildGitHubSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildAppearanceSection(context, cfg),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // ① 订阅输入
  // ═══════════════════════════════════════════════════════

  Widget _buildSubscriptionInput(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: '订阅输入',
      icon: Icons.rss_feed,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 输入模式
          SegmentedButton<String>(
            selected: {cfg.subInputMode},
            onSelectionChanged: (s) => _save(cfg.copyWith(subInputMode: s.first)),
            segments: const [
              ButtonSegment(value: 'node', label: Text('订阅器')),
              ButtonSegment(value: 'url', label: Text('订阅链接')),
              ButtonSegment(value: 'both', label: Text('两者')),
            ],
          ),
          const SizedBox(height: 16),

          // 订阅器列表
          if (cfg.subInputMode == 'node' || cfg.subInputMode == 'both') ...[
            _buildGeneratorList(context, cfg),
            const SizedBox(height: 16),
          ],

          // 订阅链接列表
          if (cfg.subInputMode == 'url' || cfg.subInputMode == 'both') ...[
            _buildUrlList(context, cfg),
            const SizedBox(height: 16),
          ],

          // 节点参数（紧凑网格布局）
          _buildNodeParams(context, cfg),
        ],
      ),
    );
  }

  /// 订阅器列表：带批量操作和紧凑卡片样式
  Widget _buildGeneratorList(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    final disabled = cfg.subDisabledGenerators;
    final enabledCount = cfg.subGenerators.length - disabled.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏 + 批量操作
        Row(
          children: [
            Icon(Icons.dns, size: 16, color: AppTheme.edgeOrange),
            const SizedBox(width: 6),
            Text('订阅器', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
            const Spacer(),
            Text('$enabledCount/${cfg.subGenerators.length} 启用',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            const SizedBox(width: 8),
            // 批量全选/全不选
            _batchToggleChip(
              label: '全选',
              active: disabled.isEmpty,
              onTap: () => _save(cfg.copyWith(subDisabledGenerators: {})),
            ),
            const SizedBox(width: 4),
            _batchToggleChip(
              label: '全不选',
              active: disabled.length == cfg.subGenerators.length,
              onTap: () {
                final all = cfg.subGenerators.map(_genName).toSet();
                _save(cfg.copyWith(subDisabledGenerators: all));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 列表
        for (var i = 0; i < cfg.subGenerators.length; i++)
          _buildListItem(
            context,
            index: i,
            controller: _genCtl[i],
            isEnabled: !disabled.contains(_genName(cfg.subGenerators[i])),
            onChanged: (v) {
              final list = [...cfg.subGenerators];
              list[i] = v;
              _save(cfg.copyWith(subGenerators: list));
            },
            onToggle: () {
              final name = _genName(cfg.subGenerators[i]);
              final set = {...disabled};
              set.contains(name) ? set.remove(name) : set.add(name);
              _save(cfg.copyWith(subDisabledGenerators: set));
            },
            onDelete: () {
              final list = [...cfg.subGenerators]..removeAt(i);
              _save(cfg.copyWith(subGenerators: list));
            },
          ),

        const SizedBox(height: 8),
        // 添加按钮 + 批量粘贴
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加', style: TextStyle(fontSize: 13)),
              onPressed: () => _save(cfg.copyWith(subGenerators: [...cfg.subGenerators, '名称|域名'])),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('批量粘贴', style: TextStyle(fontSize: 13)),
              onPressed: () => _showBatchPasteDialog(
                title: '批量添加订阅器',
                hint: '每行一个，格式：名称|域名',
                onConfirm: (lines) {
                  final valid = lines.where((l) => l.contains('|')).toList();
                  if (valid.isNotEmpty) {
                    _save(cfg.copyWith(subGenerators: [...cfg.subGenerators, ...valid]));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 订阅链接列表
  Widget _buildUrlList(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    final disabled = cfg.subDisabledUrls;
    final enabledCount = cfg.subUrls.where((u) => !disabled.contains(u.trim())).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link, size: 16, color: AppTheme.edgeOrange),
            const SizedBox(width: 6),
            Text('订阅链接', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
            const Spacer(),
            Text('$enabledCount/${cfg.subUrls.length} 启用',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            const SizedBox(width: 8),
            _batchToggleChip(
              label: '全选',
              active: disabled.isEmpty && cfg.subUrls.isNotEmpty,
              onTap: () => _save(cfg.copyWith(subDisabledUrls: {})),
            ),
            const SizedBox(width: 4),
            _batchToggleChip(
              label: '全不选',
              active: cfg.subUrls.every((u) => disabled.contains(u.trim())),
              onTap: () {
                final all = cfg.subUrls.map((u) => u.trim()).toSet();
                _save(cfg.copyWith(subDisabledUrls: all));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        for (var i = 0; i < cfg.subUrls.length; i++)
          _buildListItem(
            context,
            index: i,
            controller: _urlCtl[i],
            isEnabled: !disabled.contains(cfg.subUrls[i].trim()),
            onChanged: (v) {
              final list = [...cfg.subUrls];
              list[i] = v;
              _save(cfg.copyWith(subUrls: list));
            },
            onToggle: () {
              final url = cfg.subUrls[i].trim();
              final set = {...disabled};
              set.contains(url) ? set.remove(url) : set.add(url);
              _save(cfg.copyWith(subDisabledUrls: set));
            },
            onDelete: () {
              final list = [...cfg.subUrls]..removeAt(i);
              _save(cfg.copyWith(subUrls: list));
            },
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加', style: TextStyle(fontSize: 13)),
              onPressed: () => _save(cfg.copyWith(subUrls: [...cfg.subUrls, ''])),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('批量粘贴', style: TextStyle(fontSize: 13)),
              onPressed: () => _showBatchPasteDialog(
                title: '批量添加订阅链接',
                hint: '每行一个链接',
                onConfirm: (lines) {
                  if (lines.isNotEmpty) {
                    _save(cfg.copyWith(subUrls: [...cfg.subUrls, ...lines]));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 通用列表项：紧凑卡片 + 内联开关 + 删除
  Widget _buildListItem(
    BuildContext context, {
    required int index,
    required TextEditingController controller,
    required bool isEnabled,
    required ValueChanged<String> onChanged,
    required VoidCallback onToggle,
    required VoidCallback onDelete,
  }) {
    final t = AppThemeExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: isEnabled ? t.surface : t.surfaceHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled ? t.border : t.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            // 内联开关（点击区域大，方便快速切换）
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Icon(
                  isEnabled ? Icons.toggle_on : Icons.toggle_off,
                  color: isEnabled ? AppTheme.edgeOrange : t.textDim,
                  size: 28,
                ),
              ),
            ),
            // 输入框
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: 'AppMono',
                  fontSize: 13,
                  color: isEnabled ? t.text : t.textDim,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: '输入内容…',
                  hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                ),
              ),
            ),
            // 删除按钮
            IconButton(
              icon: Icon(Icons.close, size: 16, color: t.textDim),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  /// 批量操作小标签按钮
  Widget _batchToggleChip({required String label, required bool active, required VoidCallback onTap}) {
    final t = AppThemeExt.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? AppTheme.edgeOrange.withValues(alpha: 0.15) : t.surfaceHover,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? AppTheme.edgeOrange.withValues(alpha: 0.3) : t.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: active ? AppTheme.edgeOrange : t.textDim)),
      ),
    );
  }

  /// 节点参数：2 列网格布局，更紧凑
  Widget _buildNodeParams(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.settings_ethernet, size: 16, color: AppTheme.edgeOrange),
            const SizedBox(width: 6),
            Text('节点参数', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
          ],
        ),
        const SizedBox(height: 10),
        // 2 列布局
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _compactTextField(
                label: 'Host',
                controller: _hostCtl,
                onChanged: (v) => _save(cfg.copyWith(subNodeHost: v)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _compactTextField(
                label: 'UUID',
                controller: _uuidCtl,
                onChanged: (v) => _save(cfg.copyWith(subNodeUuid: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _compactTextField(
                label: '默认国家码',
                controller: _countryCtl,
                onChanged: (v) => _save(cfg.copyWith(subDefaultCountry: v.toUpperCase())),
                hint: '留空=不设',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _compactTextField(
                label: '输出文件名',
                controller: _latencyOutCtl,
                onChanged: (v) => _save(cfg.copyWith(subLatencyOutputFile: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 解析域名开关
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: SwitchListTile(
            title: Text('解析域名为 IP', style: TextStyle(fontSize: 13, color: t.text)),
            subtitle: Text('关闭则保留域名原样', style: TextStyle(fontSize: 12, color: t.textDim)),
            value: cfg.subResolveDomain,
            onChanged: (v) => _save(cfg.copyWith(subResolveDomain: v)),
            activeThumbColor: AppTheme.edgeOrange,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
      ],
    );
  }

  /// 紧凑输入框（带标签在上方）
  Widget _compactTextField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
    bool obscure = false,
  }) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: onChanged,
          obscureText: obscure,
          style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppTheme.edgeOrange, width: 1.5),
            ),
            filled: true,
            fillColor: t.surface,
          ),
        ),
      ],
    );
  }

  /// 批量粘贴对话框
  void _showBatchPasteDialog({
    required String title,
    required String hint,
    required void Function(List<String> lines) onConfirm,
  }) {
    final ctl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = AppThemeExt.of(ctx);
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hint, style: TextStyle(fontSize: 13, color: t.textDim)),
                const SizedBox(height: 12),
                TextField(
                  controller: ctl,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '在此粘贴，每行一个…',
                    hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final lines = ctl.text
                    .split('\n')
                    .map((l) => l.trim())
                    .where((l) => l.isNotEmpty)
                    .toList();
                if (lines.isNotEmpty) onConfirm(lines);
                Navigator.pop(ctx);
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  String _genName(String entry) => entry.split('|').first.trim();

  // ═══════════════════════════════════════════════════════
  // ② 订阅抓取
  // ═══════════════════════════════════════════════════════

  Widget _buildFetchSection(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: '订阅抓取',
      icon: Icons.cloud_sync,
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: labeledSliderCountUp(context, '连接超时 (秒)',
                    cfg.subFetchConnectTimeout.toDouble(), 1, 30,
                    (v) => _save(cfg.copyWith(subFetchConnectTimeout: v.round()))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: labeledSliderCountUp(context, '总超时 (秒)',
                    cfg.subFetchTimeout.toDouble(), 5, 60,
                    (v) => _save(cfg.copyWith(subFetchTimeout: v.round()))),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: labeledSliderCountUp(context, '重试次数 (0=不重试)',
                    cfg.subFetchMaxRetries.toDouble(), 0, 5,
                    (v) => _save(cfg.copyWith(subFetchMaxRetries: v.round()))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: labeledDoubleSliderCountUp(context, '重试间隔 (秒)',
                    cfg.subFetchRetryDelay, 0.1, 10,
                    (v) => _save(cfg.copyWith(subFetchRetryDelay: v))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppThemeExt.of(context).surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppThemeExt.of(context).border),
            ),
            child: SwitchListTile(
              title: Text('⚠️ 跳过 TLS 证书校验', style: TextStyle(fontSize: 13, color: AppThemeExt.of(context).text)),
              subtitle: Text('自签/过期证书源才开启', style: TextStyle(fontSize: 12, color: AppThemeExt.of(context).textDim)),
              value: cfg.subInsecure,
              onChanged: (v) => _save(cfg.copyWith(subInsecure: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 16),
          _buildAutoUpdate(context, cfg),
        ],
      ),
    );
  }

  Widget _buildAutoUpdate(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: Text('定时自动更新', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
            subtitle: Text('按间隔自动抓取订阅并优选', style: TextStyle(fontSize: 12, color: t.textDim)),
            value: cfg.subAutoUpdateEnabled,
            onChanged: (v) => _save(cfg.copyWith(subAutoUpdateEnabled: v)),
            activeThumbColor: AppTheme.edgeOrange,
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          if (cfg.subAutoUpdateEnabled) ...[
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: labeledSliderCountUp(context, '更新间隔（分钟）',
                  cfg.subAutoUpdateIntervalMin.toDouble(), 5, 480,
                  (v) => _save(cfg.copyWith(subAutoUpdateIntervalMin: v.round())),
                  suffix: ' 分钟'),
            ),
            SwitchListTile(
              title: Text('更新后自动运行延迟优选', style: TextStyle(fontSize: 13, color: t.text)),
              value: cfg.subAutoUpdateRunLatency,
              onChanged: (v) => _save(cfg.copyWith(subAutoUpdateRunLatency: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ④ GitHub 推送
  // ═══════════════════════════════════════════════════════

  Widget _buildGitHubSection(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: 'GitHub 推送',
      icon: Icons.cloud_upload,
      initiallyExpanded: false,
      child: Column(
        children: [
          _compactTextField(
            label: 'Token',
            controller: _tokenCtl,
            onChanged: (v) => _save(cfg.copyWith(githubToken: v)),
            obscure: true,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _compactTextField(
                  label: '仓库 (owner/repo)',
                  controller: _repoCtl,
                  onChanged: (v) => _save(cfg.copyWith(githubRepo: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compactTextField(
                  label: '分支',
                  controller: _branchCtl,
                  onChanged: (v) => _save(cfg.copyWith(githubBranch: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ④ 外观
  // ═══════════════════════════════════════════════════════

  Widget _buildAppearanceSection(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: '外观',
      icon: Icons.palette_outlined,
      initiallyExpanded: false,
      child: SegmentedButton<ThemeMode>(
        selected: {ref.watch(themeModeProvider)},
        onSelectionChanged: (s) {
          final mode = s.first;
          ref.read(themeModeProvider.notifier).state = mode;
          final themeStr = mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system';
          _save(cfg.copyWith(guiTheme: themeStr));
        },
        segments: const [
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16), label: Text('跟随系统')),
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16), label: Text('浅色')),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16), label: Text('深色')),
        ],
      ),
    );
  }
}
