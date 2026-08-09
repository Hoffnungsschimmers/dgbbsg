import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
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

  // 去抖保存：300ms 内多次变更只触发一次 SharedPreferences 写。
  Timer? _saveTimer;
  AppConfig? _pendingCfg;
  // 同步守卫：程序化设置 ctl.text 时抑制 onChanged → _save 循环。
  bool _isSyncing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 监听配置变化，在 listener 中同步 controller（而非 build()）
    ref.listenManual(configProvider, (_, next) {
      next.whenData((cfg) => _syncControllers(cfg));
    });
  }

  @override
  void dispose() {
    for (final c in _genCtl) {
      c.dispose();
    }
    for (final c in _urlCtl) {
      c.dispose();
    }
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

  void _syncList(
    List<TextEditingController> ctl,
    List<String> values,
  ) {
    while (ctl.length < values.length) {
      ctl.add(TextEditingController());
    }
    while (ctl.length > values.length) {
      ctl.removeLast().dispose();
    }
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

  /// 去抖保存：缓存最新 cfg，300ms 后批量写入 SharedPreferences。
  /// 程序化同步期间跳过（防止 _syncControllers → onChanged → _save 循环）。
  void _save(AppConfig cfg) {
    if (_isSyncing) return;
    _pendingCfg = cfg;
    _saveTimer?.cancel();
    _saveTimer = Timer(Motion.saveDebounce, () async {
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
        // 首次加载时同步 controllers（后续通过 ref.listen 自动同步）
        if (_genCtl.isEmpty && cfg.subGenerators.isNotEmpty) {
          _syncControllers(cfg);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- ① 订阅输入（默认展开）----
              SectionCollapsible(
                title: '订阅输入',
                icon: Icons.rss_feed,
                initiallyExpanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '输入模式'),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      selected: {cfg.subInputMode},
                      onSelectionChanged: (s) => _save(cfg.copyWith(subInputMode: s.first)),
                      segments: const [
                        ButtonSegment(value: 'node', label: Text('订阅器')),
                        ButtonSegment(value: 'url', label: Text('订阅链接')),
                        ButtonSegment(value: 'both', label: Text('两者')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildGenerators(context, cfg),
                    const SizedBox(height: 12),
                    _buildUrls(context, cfg),
                    const SizedBox(height: 12),
                    sectionTitle(context, '节点参数'),
                    const SizedBox(height: 8),
                    labeledTextField(context, '订阅器 Host（用于生成订阅请求）', _hostCtl,
                        (v) => _save(cfg.copyWith(subNodeHost: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '订阅器 UUID（用于生成订阅请求）', _uuidCtl,
                        (v) => _save(cfg.copyWith(subNodeUuid: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '默认国家码（无法识别时的兜底，留空=不设）', _countryCtl,
                        (v) => _save(cfg.copyWith(subDefaultCountry: v.toUpperCase()))),
                    const SizedBox(height: 8),
                    labeledSwitch(context, '解析域名为 IP（关闭则保留域名原样）', cfg.subResolveDomain,
                        (v) => _save(cfg.copyWith(subResolveDomain: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- ② 延迟优选（默认展开）----
              SectionCollapsible(
                title: '延迟优选',
                icon: Icons.speed,
                initiallyExpanded: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labeledSliderCountUp(context, '仅保留延迟低于 (ms)', cfg.subLatencyMaxMs.toDouble(), 10, 1000,
                        (v) => _save(cfg.copyWith(subLatencyMaxMs: v.round()))),
                    const SizedBox(height: 8),
                    labeledSliderCountUp(context, '保留前 N 名 (按延迟, 0=全部)', cfg.subLatencyTopN.toDouble(), 0, 500,
                        (v) => _save(cfg.copyWith(subLatencyTopN: v.round()))),
                    const SizedBox(height: 8),
                    labeledDoubleSliderCountUp(context, '最低成功率（0.0 ~ 1.0）', cfg.subLatencyMinSuccessRate, 0, 1,
                        (v) => _save(cfg.copyWith(subLatencyMinSuccessRate: v))),
                    const SizedBox(height: 8),
                    labeledDoubleSliderCountUp(context, '连接超时 (秒)', cfg.subLatencyTimeout, 0.1, 10,
                        (v) => _save(cfg.copyWith(subLatencyTimeout: v))),
                    const SizedBox(height: 8),
                    labeledSliderCountUp(context, '并发数', cfg.subLatencyWorkers.toDouble(), 1, 200,
                        (v) => _save(cfg.copyWith(subLatencyWorkers: v.round()))),
                    const SizedBox(height: 8),
                    labeledSliderCountUp(context, '探测次数', cfg.subLatencyProbes.toDouble(), 1, 10,
                        (v) => _save(cfg.copyWith(subLatencyProbes: v.round()))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '输出文件名', _latencyOutCtl,
                        (v) => _save(cfg.copyWith(subLatencyOutputFile: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- ③ 订阅抓取（默认折叠）----
              SectionCollapsible(
                title: '订阅抓取',
                icon: Icons.cloud_sync,
                initiallyExpanded: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labeledSliderCountUp(context, '连接超时 (秒)', cfg.subFetchConnectTimeout.toDouble(), 1, 30,
                        (v) => _save(cfg.copyWith(subFetchConnectTimeout: v.round()))),
                    const SizedBox(height: 8),
                    labeledSliderCountUp(context, '总超时 (秒)', cfg.subFetchTimeout.toDouble(), 5, 60,
                        (v) => _save(cfg.copyWith(subFetchTimeout: v.round()))),
                    const SizedBox(height: 8),
                    labeledSliderCountUp(context, '重试次数 (0=不重试)', cfg.subFetchMaxRetries.toDouble(), 0, 5,
                        (v) => _save(cfg.copyWith(subFetchMaxRetries: v.round()))),
                    const SizedBox(height: 8),
                    labeledDoubleSliderCountUp(context, '重试间隔 (秒)', cfg.subFetchRetryDelay, 0.1, 10,
                        (v) => _save(cfg.copyWith(subFetchRetryDelay: v))),
                    const SizedBox(height: 8),
                    labeledSwitch(context, '⚠️ 跳过 TLS 证书校验（自签/过期证书源才开启）', cfg.subInsecure,
                        (v) => _save(cfg.copyWith(subInsecure: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- ④ GitHub 推送（默认折叠）----
              SectionCollapsible(
                title: 'GitHub 推送',
                icon: Icons.cloud_upload,
                initiallyExpanded: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labeledTextField(context, 'Token', _tokenCtl,
                        (v) => _save(cfg.copyWith(githubToken: v)), obscure: true),
                    const SizedBox(height: 8),
                    labeledTextField(context, '仓库 (owner/repo)', _repoCtl,
                        (v) => _save(cfg.copyWith(githubRepo: v))),
                    const SizedBox(height: 8),
                    labeledTextField(context, '分支', _branchCtl,
                        (v) => _save(cfg.copyWith(githubBranch: v))),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- ⑤ 外观（默认折叠，三档主题）----
              SectionCollapsible(
                title: '外观',
                icon: Icons.palette_outlined,
                initiallyExpanded: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle(context, '主题模式'),
                    const SizedBox(height: 8),
                    SegmentedButton<ThemeMode>(
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGenerators(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    final disabled = cfg.subDisabledGenerators;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(context, '订阅器（格式：名称|域名 或 名称|域名|密钥）'),
        const SizedBox(height: 8),
        for (var i = 0; i < cfg.subGenerators.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _genCtl[i],
                    onChanged: (v) {
                      final list = [...cfg.subGenerators];
                      list[i] = v;
                      _save(cfg.copyWith(subGenerators: list));
                    },
                    style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                    decoration: inputDecorationFor(context),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: disabled.contains(_genName(cfg.subGenerators[i])) ? '启用' : '禁用',
                  icon: Icon(disabled.contains(_genName(cfg.subGenerators[i]))
                      ? Icons.toggle_off : Icons.toggle_on,
                      color: disabled.contains(_genName(cfg.subGenerators[i]))
                          ? null : AppTheme.edgeOrange),
                  onPressed: () {
                    final name = _genName(cfg.subGenerators[i]);
                    final set = {...disabled};
                    if (set.contains(name)) {
                      set.remove(name);
                    } else {
                      set.add(name);
                    }
                    _save(cfg.copyWith(subDisabledGenerators: set));
                  },
                ),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(Icons.delete_outline, color: t.danger),
                  onPressed: () {
                    final list = [...cfg.subGenerators]..removeAt(i);
                    _save(cfg.copyWith(subGenerators: list));
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('添加订阅器'),
          onPressed: () => _save(cfg.copyWith(subGenerators: [...cfg.subGenerators, '名称|域名'])),
        ),
      ],
    );
  }

  Widget _buildUrls(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(context, '订阅链接（支持 http(s)、sub://、纯 IP 列表）'),
        const SizedBox(height: 8),
        for (var i = 0; i < cfg.subUrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlCtl[i],
                    onChanged: (v) {
                      final list = [...cfg.subUrls];
                      list[i] = v;
                      _save(cfg.copyWith(subUrls: list));
                    },
                    style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
                    decoration: inputDecorationFor(context),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: cfg.subDisabledUrls.contains(cfg.subUrls[i].trim()) ? '启用' : '禁用',
                  icon: Icon(
                    cfg.subDisabledUrls.contains(cfg.subUrls[i].trim())
                        ? Icons.toggle_off : Icons.toggle_on,
                    color: cfg.subDisabledUrls.contains(cfg.subUrls[i].trim())
                        ? null : AppTheme.edgeOrange,
                  ),
                  onPressed: () {
                    final url = cfg.subUrls[i].trim();
                    final set = {...cfg.subDisabledUrls};
                    if (set.contains(url)) {
                      set.remove(url);
                    } else {
                      set.add(url);
                    }
                    _save(cfg.copyWith(subDisabledUrls: set));
                  },
                ),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(Icons.delete_outline, color: t.danger),
                  onPressed: () {
                    final list = [...cfg.subUrls]..removeAt(i);
                    _save(cfg.copyWith(subUrls: list));
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('添加订阅链接'),
          onPressed: () => _save(cfg.copyWith(subUrls: [...cfg.subUrls, ''])),
        ),
      ],
    );
  }

  String _genName(String entry) => entry.split('|').first.trim();
}
