import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../widgets/common.dart';
import 'config_entries.dart';
import 'config_item_widgets.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});
  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> with AutomaticKeepAliveClientMixin {
  final _hostCtl = TextEditingController();
  final _hostFocus = FocusNode();
  final _uuidCtl = TextEditingController();
  final _uuidFocus = FocusNode();
  final _countryCtl = TextEditingController();
  final _countryFocus = FocusNode();
  final _landingOutCtl = TextEditingController();
  final _probeEgressCtl = TextEditingController();
  final _probeEgressFocus = FocusNode();
  final _landingOutFocus = FocusNode();
  final _tokenCtl = TextEditingController();
  final _tokenFocus = FocusNode();
  final _repoCtl = TextEditingController();
  final _repoFocus = FocusNode();
  final _branchCtl = TextEditingController();
  final _branchFocus = FocusNode();
  final _wdUrlCtl = TextEditingController();
  final _wdUrlFocus = FocusNode();
  final _wdUserCtl = TextEditingController();
  final _wdUserFocus = FocusNode();
  final _wdPassCtl = TextEditingController();
  final _wdPassFocus = FocusNode();
  final _wdIntervalCtl = TextEditingController();
  final _wdIntervalFocus = FocusNode();
  final _webhookUrlCtl = TextEditingController();
  final _webhookUrlFocus = FocusNode();
  final _pushMinCtl = TextEditingController();
  final _pushMinFocus = FocusNode();

  Timer? _saveTimer;
  AppConfig? _pendingCfg;
  bool _isSyncing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // fireImmediately：配置可能在本页挂载前就已解析完（主窗口先读过），
    // 此时不补发当前值会让所有输入框停在空状态。
    ref.listenManual(configProvider, (_, next) {
      next.whenData((cfg) {
        _syncControllers(cfg);
        // 启动时初始化 latestConfigProvider，确保运行时读到正确配置。
        // fireImmediately 时回调发生在 initState 内，改 provider 必须推到帧后。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(latestConfigProvider.notifier).state ??= cfg;
          }
        });
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _hostFocus.dispose();
    _uuidCtl.dispose();
    _uuidFocus.dispose();
    _countryCtl.dispose();
    _countryFocus.dispose();
    _landingOutCtl.dispose();
    _probeEgressCtl.dispose();
    _probeEgressFocus.dispose();
    _landingOutFocus.dispose();
    _tokenCtl.dispose();
    _tokenFocus.dispose();
    _repoCtl.dispose();
    _repoFocus.dispose();
    _branchCtl.dispose();
    _branchFocus.dispose();
    _wdUrlCtl.dispose();
    _wdUrlFocus.dispose();
    _wdUserCtl.dispose();
    _wdUserFocus.dispose();
    _wdPassCtl.dispose();
    _wdPassFocus.dispose();
    _wdIntervalCtl.dispose();
    _wdIntervalFocus.dispose();
    _webhookUrlCtl.dispose();
    _webhookUrlFocus.dispose();
    _pushMinCtl.dispose();
    _pushMinFocus.dispose();
    _saveTimer?.cancel();
    super.dispose();
  }

  /// 同步单个字段。正在编辑（聚焦）时跳过，避免覆盖用户输入并破坏选区。
  /// 回写时给出合法选区（text= setter 会产生 offset:-1 的非法选区，
  /// Windows 平台会把非法选区修复成「全选」）。
  void _syncIf(TextEditingController ctl, FocusNode focus, String v) {
    if (ctl.text != v && !focus.hasFocus) {
      ctl.value = TextEditingValue(
        text: v,
        selection: TextSelection.collapsed(offset: v.length),
      );
    }
  }

  void _syncControllers(AppConfig cfg) {
    _isSyncing = true;
    _syncIf(_pushMinCtl, _pushMinFocus, '${cfg.pushMinimumNodes}');
    _syncIf(_hostCtl, _hostFocus, cfg.subNodeHost);
    _syncIf(_uuidCtl, _uuidFocus, cfg.subNodeUuid);
    _syncIf(_countryCtl, _countryFocus, cfg.subDefaultCountry);
    _syncIf(_tokenCtl, _tokenFocus, cfg.githubToken);
    _syncIf(_repoCtl, _repoFocus, cfg.githubRepo);
    _syncIf(_branchCtl, _branchFocus, cfg.githubBranch);
    _syncIf(_wdUrlCtl, _wdUrlFocus, cfg.webdavUrl);
    _syncIf(_wdUserCtl, _wdUserFocus, cfg.webdavUser);
    _syncIf(_wdPassCtl, _wdPassFocus, cfg.webdavPassword);
    _syncIf(_wdIntervalCtl, _wdIntervalFocus, cfg.webdavAutoSyncIntervalMin.toString());
    _syncIf(_webhookUrlCtl, _webhookUrlFocus, cfg.webhookUrl);
    _syncIf(_landingOutCtl, _landingOutFocus, cfg.landingOutputFile);
    _syncIf(_probeEgressCtl, _probeEgressFocus, cfg.probeEgresses.join('\n'));
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
      try {
        final repo = await ref.read(configRepositoryProvider.future);
        await repo.save(c);
        if (mounted) ref.invalidate(configProvider);
      } catch (e) {
        if (mounted) AppToast.show(context, '配置保存失败：$e', success: false);
      }
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
        final validationErrors = cfg.validate();
        final t = AppThemeExt.of(context);
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
                    // 自动保存提示（轻量，不打扰）
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(Icons.autorenew, size: 13, color: t.textDim),
                          const SizedBox(width: 6),
                          Text('所有修改自动保存，无需手动保存',
                              style: TextStyle(fontSize: 12, color: t.textDim)),
                        ],
                      ),
                    ),
                    _buildSubscriptionInput(context, cfg),
                    const SizedBox(height: 12),
                    _buildNodeParamsSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildFetchSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildEgressSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildWebhookSection(context, cfg),
                    const SizedBox(height: 12),
                    _buildGitHubSection(context, cfg),
                    const SizedBox(height: 14),
                    _buildWebDavSection(context, cfg),
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
    final t = AppThemeExt.of(context);
    return SectionCollapsible(
      title: '订阅输入',
      icon: Icons.rss_feed,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 输入模式（手机端可换行，点击区域大）
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in const [
                ('node', '订阅器'),
                ('url', '订阅链接'),
                ('both', '两者'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 14)),
                  selected: cfg.subInputMode == value,
                  showCheckmark: false,
                  selectedColor: AppTheme.edgeOrange.withValues(alpha: 0.2),
                  side: BorderSide(color: t.border),
                  onSelected: (_) => _save(cfg.copyWith(subInputMode: value)),
                ),
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
        ],
      ),
    );
  }

  /// ② 节点参数（独立折叠组）。
  Widget _buildNodeParamsSection(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: '节点参数',
      icon: Icons.settings_ethernet,
      initiallyExpanded: true,
      child: _buildNodeParams(context, cfg),
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
            const Icon(Icons.dns, size: 16, color: AppTheme.edgeOrange),
            const SizedBox(width: 6),
            Text('订阅器', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
            const Spacer(),
            Text('$enabledCount/${cfg.subGenerators.length} 启用',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            const SizedBox(width: 8),
            // 批量全选/全不选
            batchToggleChip(context, 
              label: '全选',
              active: disabled.isEmpty,
              onTap: () => _save(cfg.copyWith(subDisabledGenerators: {})),
            ),
            const SizedBox(width: 4),
            batchToggleChip(context, 
              label: '全不选',
              active: disabled.length == cfg.subGenerators.length,
              onTap: () {
                final all = cfg.subGenerators.map(generatorName).toSet();
                _save(cfg.copyWith(subDisabledGenerators: all));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 列表
        for (var i = 0; i < cfg.subGenerators.length; i++)
          buildItemCard(
            context,
            note: generatorName(cfg.subGenerators[i]),
            value: generatorHost(cfg.subGenerators[i]),
            isEnabled: !disabled.contains(generatorName(cfg.subGenerators[i])),
            onTapEdit: () => showItemEditor(context, 
              title: '编辑订阅器',
              noteLabel: '备注',
              valueLabel: '域名',
              showSecret: true,
              secretLabel: '密钥（可选）',
              note: generatorName(cfg.subGenerators[i]),
              value: generatorHost(cfg.subGenerators[i]),
              secret: generatorSecret(cfg.subGenerators[i]),
              onSave: (note, value, secret) {
                // 备注为空时回退用域名，保证 `名称|域名` 格式不断裂。
                final name = note.isEmpty ? value : note;
                final list = [...cfg.subGenerators];
                list[i] = secret.isNotEmpty ? '$name|$value|$secret' : '$name|$value';
                _save(cfg.copyWith(subGenerators: list));
              },
            ),
            onToggle: () {
              final name = generatorName(cfg.subGenerators[i]);
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
              onPressed: () => showItemEditor(context, 
                title: '添加订阅器',
                noteLabel: '备注',
                valueLabel: '域名',
                showSecret: true,
                secretLabel: '密钥（可选）',
                onSave: (note, value, secret) {
                  final name = note.isEmpty ? value : note;
                  final entry =
                      secret.isNotEmpty ? '$name|$value|$secret' : '$name|$value';
                  _save(cfg.copyWith(subGenerators: [...cfg.subGenerators, entry]));
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('批量粘贴', style: TextStyle(fontSize: 13)),
              onPressed: () => showBatchPasteDialog(context, 
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
            const Icon(Icons.link, size: 16, color: AppTheme.edgeOrange),
            const SizedBox(width: 6),
            Text('订阅链接', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
            const Spacer(),
            Text('$enabledCount/${cfg.subUrls.length} 启用',
                style: TextStyle(fontSize: 12, color: t.textDim)),
            const SizedBox(width: 8),
            batchToggleChip(context, 
              label: '全选',
              active: disabled.isEmpty && cfg.subUrls.isNotEmpty,
              onTap: () => _save(cfg.copyWith(subDisabledUrls: {})),
            ),
            const SizedBox(width: 4),
            batchToggleChip(context, 
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
          buildItemCard(
            context,
            note: urlNote(cfg.subUrls[i]),
            value: urlValue(cfg.subUrls[i]),
            isEnabled: !disabled.contains(cfg.subUrls[i].trim()),
            onTapEdit: () => showItemEditor(context, 
              title: '编辑订阅链接',
              noteLabel: '备注',
              valueLabel: '链接',
              note: urlNote(cfg.subUrls[i]),
              value: urlValue(cfg.subUrls[i]),
              onSave: (note, value, _) {
                final list = [...cfg.subUrls];
                list[i] = joinNoteValue(note, value);
                _save(cfg.copyWith(subUrls: list));
              },
            ),
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
              onPressed: () => showItemEditor(context, 
                title: '添加订阅链接',
                noteLabel: '备注',
                valueLabel: '链接',
                onSave: (note, value, _) {
                  _save(cfg.copyWith(subUrls: [...cfg.subUrls, joinNoteValue(note, value)]));
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.content_paste, size: 18),
              label: const Text('批量粘贴', style: TextStyle(fontSize: 13)),
              onPressed: () => showBatchPasteDialog(context, 
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

  /// 节点参数内容：宽屏 2 列网格，窄屏（手机）单列全宽。
  Widget _buildNodeParams(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 宽屏 2 列 / 窄屏单列
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _compactTextField(
                  label: 'Host',
                  controller: _hostCtl,
                  focusNode: _hostFocus,
                  onChanged: (v) => _save(cfg.copyWith(subNodeHost: v.trim())),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compactTextField(
                  label: 'UUID',
                  controller: _uuidCtl,
                  focusNode: _uuidFocus,
                  onChanged: (v) => _save(cfg.copyWith(subNodeUuid: v.trim())),
                ),
              ),
            ],
          )
        else ...[
          _compactTextField(
            label: 'Host',
            controller: _hostCtl,
            focusNode: _hostFocus,
            onChanged: (v) => _save(cfg.copyWith(subNodeHost: v.trim())),
          ),
          const SizedBox(height: 12),
          _compactTextField(
            label: 'UUID',
            controller: _uuidCtl,
            focusNode: _uuidFocus,
            onChanged: (v) => _save(cfg.copyWith(subNodeUuid: v.trim())),
          ),
        ],
        const SizedBox(height: 12),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _compactTextField(
                  label: '默认国家码',
                  controller: _countryCtl,
                  focusNode: _countryFocus,
                  onChanged: (v) => _save(cfg.copyWith(subDefaultCountry: v.trim().toUpperCase())),
                  hint: '留空=不设',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compactTextField(
                  label: '落地/推送文件名',
                  controller: _landingOutCtl,
                  focusNode: _landingOutFocus,
                  onChanged: (v) => _save(cfg.copyWith(landingOutputFile: v)),
                ),
              ),
            ],
          )
        else ...[
          _compactTextField(
            label: '默认国家码',
            controller: _countryCtl,
            focusNode: _countryFocus,
            onChanged: (v) => _save(cfg.copyWith(subDefaultCountry: v.trim().toUpperCase())),
            hint: '留空=不设',
          ),
          const SizedBox(height: 12),
          _compactTextField(
            label: '落地/推送文件名',
            controller: _landingOutCtl,
            focusNode: _landingOutFocus,
            onChanged: (v) => _save(cfg.copyWith(landingOutputFile: v)),
          ),
        ],
        const SizedBox(height: 12),
        // 解析域名开关
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.border),
          ),
          child: Material(
            type: MaterialType.transparency,
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
        ),
      ],
    );
  }

  /// 紧凑输入框（带标签在上方）
  Widget _compactTextField({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
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
          focusNode: focusNode,
          onChanged: onChanged,
          obscureText: obscure,
          style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  // ═══════════════════════════════════════════════════════
  // ② 订阅抓取
  // ═══════════════════════════════════════════════════════

  Widget _buildFetchSection(BuildContext context, AppConfig cfg) {
    return SectionCollapsible(
      title: '订阅抓取',
      icon: Icons.cloud_sync,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: labeledSliderCountUp(context, '连接超时 (秒)',
                    cfg.subFetchConnectTimeout.toDouble(), 3, 30,
                    (v) => _save(cfg.copyWith(subFetchConnectTimeout: v.round()))),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: labeledSliderCountUp(context, '总超时 (秒)',
                    cfg.subFetchTimeout.toDouble(), 5, 120,
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
                    cfg.subFetchRetryDelay, 0.5, 10,
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
            child: Material(
              type: MaterialType.transparency,
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
          ),
          const SizedBox(height: 16),
          _buildAutoUpdate(context, cfg),
        ],
      ),
    );
  }

  // ③ 落地检测：无参数可配（强制直连），输出文件在「输出」区块设置。

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
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              title: Text('定时自动更新', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
              subtitle: Text('软件运行期间按间隔执行；已有任务时跳过', style: TextStyle(fontSize: 12, color: t.textDim)),
              value: cfg.subAutoUpdateEnabled,
              onChanged: (v) => _save(cfg.copyWith(subAutoUpdateEnabled: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          if (cfg.subAutoUpdateEnabled) ...[
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: DropdownButtonFormField<String>(
                initialValue: ['subscription', 'landing', 'pipeline'].contains(cfg.subAutoUpdateMode) ? cfg.subAutoUpdateMode : 'subscription',
                decoration: const InputDecoration(labelText: '自动任务内容'),
                items: const [
                  DropdownMenuItem(value: 'subscription', child: Text('仅获取订阅')),
                  DropdownMenuItem(value: 'landing', child: Text('获取订阅并检测落地')),
                  DropdownMenuItem(value: 'pipeline', child: Text('获取、检测并推送 GitHub')),
                ],
                onChanged: (value) { if (value != null) _save(cfg.copyWith(subAutoUpdateMode: value)); },
              )),
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: labeledSliderCountUp(context, '更新间隔（分钟）',
                  cfg.subAutoUpdateIntervalMin.toDouble(), 10, 720,
                  (v) => _save(cfg.copyWith(subAutoUpdateIntervalMin: v.round())),
                  suffix: ' 分钟'),
            ),
          ],
          Divider(height: 1, color: t.border),
          Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('推送保护（自动和手动均生效）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: t.text)),
              const SizedBox(height: 6),
              Text('GeoIP 估计不计入实测。未达到门槛时保存结果并说明原因。', style: TextStyle(fontSize: 12, color: t.textDim)),
              TextField(
                controller: _pushMinCtl,
                focusNode: _pushMinFocus,
                decoration: const InputDecoration(labelText: '最少有效节点数'),
                keyboardType: TextInputType.number,
                onChanged: (text) {
                  final n = int.tryParse(text);
                  if (n != null && n > 0) _save(cfg.copyWith(pushMinimumNodes: n));
                },
              ),
              labeledSliderCountUp(context, '最低 POP 实测比例',
                cfg.pushMinimumMeasuredRatio * 100, 0, 100,
                (v) => _save(cfg.copyWith(pushMinimumMeasuredRatio: v / 100)), suffix: '%'),
              labeledSliderCountUp(context, '相对上次最少保留',
                cfg.pushMinimumRetainedRatio * 100, 0, 100,
                (v) => _save(cfg.copyWith(pushMinimumRetainedRatio: v / 100)), suffix: '%'),
            ],
          )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════
  // ③′ 探测出口（多出口对照用）
  // ═══════════════════════════════════════════════════════

  /// 多出口对照探测的出口清单：每行一条 `名称|host:port`，`|` 后留空即直连。
  Widget _buildEgressSection(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return SectionCollapsible(
      title: '探测出口（多出口对照）',
      icon: Icons.compare_arrows,
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _probeEgressCtl,
            focusNode: _probeEgressFocus,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
            decoration: InputDecoration(
              labelText: '出口清单（每行一条：名称|host:port，留空 host 即直连）',
              labelStyle: TextStyle(fontSize: 13, color: t.textDim),
              hintText: '本机直连|\n节点A|127.0.0.1:7890',
              hintStyle: TextStyle(fontSize: 12, color: t.textDim),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: t.radius),
            ),
            onChanged: (v) => _save(cfg.copyWith(
              probeEgresses:
                  v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            )),
          ),
          const SizedBox(height: 4),
          Text(
            '运行页「多出口对照」会让同一批 IP 依次经这些出口做 cdn-cgi/trace，'
            '产出 CSV 对照表并写入落地历史。落地检测本身始终直连，不受此处影响。',
            style: TextStyle(fontSize: 12, color: t.textDim),
          ),
        ],
      ),
    );
  }

  // ④ GitHub 推送
  // ═══════════════════════════════════════════════════════

  Widget _buildGitHubSection(BuildContext context, AppConfig cfg) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return SectionCollapsible(
      title: 'GitHub 推送',
      icon: Icons.cloud_upload,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _compactTextField(
            label: 'Token',
            controller: _tokenCtl,
            focusNode: _tokenFocus,
            onChanged: (v) => _save(cfg.copyWith(githubToken: v.trim())),
            obscure: true,
          ),
          const SizedBox(height: 12),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _compactTextField(
                    label: '仓库 (owner/repo)',
                    controller: _repoCtl,
                    focusNode: _repoFocus,
                    onChanged: (v) => _save(cfg.copyWith(githubRepo: v.trim())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _compactTextField(
                    label: '分支',
                    controller: _branchCtl,
                    focusNode: _branchFocus,
                    onChanged: (v) => _save(cfg.copyWith(githubBranch: v.trim())),
                  ),
                ),
              ],
            )
          else ...[
            _compactTextField(
              label: '仓库 (owner/repo)',
              controller: _repoCtl,
              focusNode: _repoFocus,
              onChanged: (v) => _save(cfg.copyWith(githubRepo: v.trim())),
            ),
            const SizedBox(height: 12),
            _compactTextField(
              label: '分支',
              controller: _branchCtl,
              focusNode: _branchFocus,
              onChanged: (v) => _save(cfg.copyWith(githubBranch: v.trim())),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ④ Webhook 通知
  // ═══════════════════════════════════════════════════════

  /// Webhook 通知：类型选择 + URL + 完成/失败开关。
  /// 与 _notifyWebhook 的读取一致：type=none 或 URL 为空时不发送。
  Widget _buildWebhookSection(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return SectionCollapsible(
      title: 'Webhook 通知',
      icon: Icons.notifications_outlined,
      initiallyExpanded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in const [
                ('none', '关闭'),
                ('telegram', 'Telegram'),
                ('discord', 'Discord'),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 14)),
                  selected: cfg.webhookType == value,
                  showCheckmark: false,
                  selectedColor: AppTheme.edgeOrange.withValues(alpha: 0.2),
                  side: BorderSide(color: t.border),
                  onSelected: (_) => _save(cfg.copyWith(webhookType: value)),
                ),
            ],
          ),
          if (cfg.webhookType != 'none') ...[
            const SizedBox(height: 12),
            _compactTextField(
              label: cfg.webhookType == 'telegram' ? 'Bot 地址（…/sendMessage?chat_id=…）' : 'Webhook 地址',
              controller: _webhookUrlCtl,
              focusNode: _webhookUrlFocus,
              onChanged: (v) => _save(cfg.copyWith(webhookUrl: v.trim())),
              hint: 'https://…',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text('任务完成时通知', style: TextStyle(fontSize: 13, color: t.text)),
              value: cfg.webhookOnComplete,
              onChanged: (v) => _save(cfg.copyWith(webhookOnComplete: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            SwitchListTile(
              title: Text('任务失败时通知', style: TextStyle(fontSize: 13, color: t.text)),
              value: cfg.webhookOnError,
              onChanged: (v) => _save(cfg.copyWith(webhookOnError: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ④ WebDAV 同步
  // ═══════════════════════════════════════════════════════

  Widget _buildWebDavSection(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return SectionCollapsible(
      title: 'WebDAV 同步',
      icon: Icons.cloud_sync_outlined,
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '顶栏云朵按钮可手动推送备份 / 拉取恢复配置与结果文件',
            style: TextStyle(fontSize: 12, color: t.textDim),
          ),
          const SizedBox(height: 12),
          _compactTextField(
            label: '服务器地址',
            controller: _wdUrlCtl,
            focusNode: _wdUrlFocus,
            onChanged: (v) => _save(cfg.copyWith(webdavUrl: v.trim())),
            hint: 'https://dav.jianguoyun.com/dav',
          ),
          const SizedBox(height: 12),
          _compactTextField(
            label: '账号',
            controller: _wdUserCtl,
            focusNode: _wdUserFocus,
            onChanged: (v) => _save(cfg.copyWith(webdavUser: v.trim())),
          ),
          const SizedBox(height: 12),
          _compactTextField(
            label: '密码',
            controller: _wdPassCtl,
            focusNode: _wdPassFocus,
            onChanged: (v) => _save(cfg.copyWith(webdavPassword: v)),
            obscure: true,
          ),
          const SizedBox(height: 16),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              title: Text('自动同步', style: TextStyle(fontSize: 13, color: t.text)),
              subtitle: Text('开启后按间隔自动推送备份', style: TextStyle(fontSize: 12, color: t.textDim)),
              value: cfg.webdavAutoSync,
              onChanged: (v) => _save(cfg.copyWith(webdavAutoSync: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          if (cfg.webdavAutoSync) ...[
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: labeledSliderCountUp(context, '自动同步间隔（分钟）',
                  cfg.webdavAutoSyncIntervalMin.toDouble(), 10, 720,
                  (v) => _save(cfg.copyWith(webdavAutoSyncIntervalMin: v.round())),
                  suffix: ' 分钟'),
            ),
          ],
        ],
      ),
    );
  }
}
