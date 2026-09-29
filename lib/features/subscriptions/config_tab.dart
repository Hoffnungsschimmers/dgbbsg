import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/subscription/sub_parser.dart' show supportedSchemes;
import '../widgets/common.dart';

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
          _buildItemCard(
            context,
            note: _genName(cfg.subGenerators[i]),
            value: _genHost(cfg.subGenerators[i]),
            isEnabled: !disabled.contains(_genName(cfg.subGenerators[i])),
            onTapEdit: () => _showItemEditor(
              title: '编辑订阅器',
              noteLabel: '备注',
              valueLabel: '域名',
              showSecret: true,
              secretLabel: '密钥（可选）',
              note: _genName(cfg.subGenerators[i]),
              value: _genHost(cfg.subGenerators[i]),
              secret: _genSecret(cfg.subGenerators[i]),
              onSave: (note, value, secret) {
                // 备注为空时回退用域名，保证 `名称|域名` 格式不断裂。
                final name = note.isEmpty ? value : note;
                final list = [...cfg.subGenerators];
                list[i] = secret.isNotEmpty ? '$name|$value|$secret' : '$name|$value';
                _save(cfg.copyWith(subGenerators: list));
              },
            ),
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
              onPressed: () => _showItemEditor(
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
            const Icon(Icons.link, size: 16, color: AppTheme.edgeOrange),
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
          _buildItemCard(
            context,
            note: _urlNote(cfg.subUrls[i]),
            value: _urlValue(cfg.subUrls[i]),
            isEnabled: !disabled.contains(cfg.subUrls[i].trim()),
            onTapEdit: () => _showItemEditor(
              title: '编辑订阅链接',
              noteLabel: '备注',
              valueLabel: '链接',
              note: _urlNote(cfg.subUrls[i]),
              value: _urlValue(cfg.subUrls[i]),
              onSave: (note, value, _) {
                final list = [...cfg.subUrls];
                list[i] = _joinNoteValue(note, value);
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
              onPressed: () => _showItemEditor(
                title: '添加订阅链接',
                noteLabel: '备注',
                valueLabel: '链接',
                onSave: (note, value, _) {
                  _save(cfg.copyWith(subUrls: [...cfg.subUrls, _joinNoteValue(note, value)]));
                },
              ),
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

  /// 列表项：静态卡片（备注 + 内容），点击整卡弹出编辑对话框。
  /// 开关与删除保持行内大点击区域，编辑通过弹窗完成（避免行内小框难输入）。
  Widget _buildItemCard(
    BuildContext context, {
    required String note,
    required String value,
    required bool isEnabled,
    required VoidCallback onTapEdit,
    required VoidCallback onToggle,
    required VoidCallback onDelete,
  }) {
    final t = AppThemeExt.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTapEdit,
          child: Ink(
            decoration: BoxDecoration(
              color: isEnabled ? t.surface : t.surfaceHover.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isEnabled ? t.border : t.border.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // 内联开关（点击区域大，方便快速切换）
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                    child: Icon(
                      isEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: isEnabled ? AppTheme.edgeOrange : t.textDim,
                      size: 30,
                    ),
                  ),
                ),
                // 备注 + 内容（静态显示，点击弹窗编辑）
                Expanded(
                  child: InkWell(
                    onTap: onTapEdit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.isEmpty ? '（未命名）' : note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isEnabled ? t.text : t.textDim,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'AppMono',
                              fontSize: 12,
                              color: isEnabled ? t.textDim : t.textDim.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 删除按钮
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: t.textDim),
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 编辑/新增条目弹窗：备注 + 内容（订阅器另有密钥）双框全宽输入。
  void _showItemEditor({
    required String title,
    required String noteLabel,
    required String valueLabel,
    required void Function(String note, String value, String secret) onSave,
    String? note,
    String? value,
    String? secret,
    bool showSecret = false,
    String? secretLabel,
  }) {
    final noteCtl = TextEditingController(text: note ?? '');
    final valueCtl = TextEditingController(text: value ?? '');
    final secretCtl = TextEditingController(text: secret ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final t = AppThemeExt.of(ctx);
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noteLabel,
                    style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('editor_note'),
                  controller: noteCtl,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '备注（显示在列表中的名称）',
                    hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text(valueLabel,
                    style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('editor_value'),
                  controller: valueCtl,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: valueLabel == '链接' ? 'https://…' : '域名',
                    hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                if (showSecret) ...[
                  const SizedBox(height: 12),
                  Text(secretLabel ?? '密钥（可选）',
                      style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  TextField(
                    key: const Key('editor_secret'),
                    controller: secretCtl,
                    style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'edgetunnel 部署 uuid 或 token',
                      hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final n = noteCtl.text.trim();
                final v = valueCtl.text.trim();
                final s = secretCtl.text.trim();
                if (v.isEmpty) {
                  AppToast.show(ctx, '$valueLabel 不能为空', success: false);
                  return;
                }
                onSave(n, v, s);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 订阅器：名称 = 第一个 | 段
  String _genName(String entry) => entry.split('|').first.trim();

  /// 订阅器：域名 = 第二个 | 段（无则整个条目）
  String _genHost(String entry) {
    final parts = entry.split('|');
    return parts.length > 1 ? parts[1].trim() : entry.trim();
  }

  /// 订阅器：密钥 = 第三个 | 段
  String _genSecret(String entry) {
    final parts = entry.split('|');
    return parts.length > 2 ? parts.sublist(2).join('|').trim() : '';
  }

  /// 订阅链接：备注 = 第一个 | 段。
  /// 节点分享链接（vless/vmess/trojan/ss/ssr/hysteria2/hy2/tuic）本身不带
  /// 「备注|」前缀；只有 http(s) 订阅地址支持标签前缀。
  /// 用 supportedSchemes 精确判断，避免把含 "://" 的备注误判为节点链接
  /// （如 "备注A|https://…" 含 :// 但仍是带标签的订阅地址）。
  String _urlNote(String url) {
    final u = url.trim();
    if (supportedSchemes.any((s) => u.startsWith(s))) return '';
    final pipeIdx = u.indexOf('|');
    if (pipeIdx > 0) return u.substring(0, pipeIdx).trim();
    return '';
  }

  /// 订阅链接：实际链接 = | 之后部分（无 | 则整体）
  String _urlValue(String url) {
    final u = url.trim();
    if (supportedSchemes.any((s) => u.startsWith(s))) return u;
    final pipeIdx = u.indexOf('|');
    if (pipeIdx > 0) {
      final after = u.substring(pipeIdx + 1).trim();
      if (after.isNotEmpty) return after;
    }
    return u;
  }

  /// 备注 + 链接 拼回存储格式（节点分享链接不拼备注）
  String _joinNoteValue(String note, String value) {
    final v = value.trim();
    if (supportedSchemes.any((s) => v.startsWith(s))) return v;
    final n = note.trim();
    return n.isEmpty ? v : '$n|$v';
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
              subtitle: Text('按间隔自动抓取订阅', style: TextStyle(fontSize: 12, color: t.textDim)),
              value: cfg.subAutoUpdateEnabled,
              onChanged: (v) => _save(cfg.copyWith(subAutoUpdateEnabled: v)),
              activeThumbColor: AppTheme.edgeOrange,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          if (cfg.subAutoUpdateEnabled) ...[
            Divider(height: 1, color: t.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: labeledSliderCountUp(context, '更新间隔（分钟）',
                  cfg.subAutoUpdateIntervalMin.toDouble(), 10, 720,
                  (v) => _save(cfg.copyWith(subAutoUpdateIntervalMin: v.round())),
                  suffix: ' 分钟'),
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
