import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../config/field_list.dart';
import '../widgets/common.dart';
import 'settings_fields.dart';

/// 设置：GitHub 推送 + 外观主题 + 附加数据源 + 关于。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final List<TextEditingController> _srcCtl = [];

  @override
  void dispose() {
    for (final c in _srcCtl) {
      c.dispose();
    }
    super.dispose();
  }

  void _syncSources(List<SourceConfig> sources) {
    while (_srcCtl.length < sources.length) {
      _srcCtl.add(TextEditingController());
    }
    while (_srcCtl.length > sources.length) {
      _srcCtl.removeLast().dispose();
    }
    for (var i = 0; i < sources.length; i++) {
      if (_srcCtl[i].text != sources[i].url) _srcCtl[i].text = sources[i].url;
    }
  }

  Future<void> _saveKey(Map<String, dynamic> draft, String key, dynamic value) async {
    draft[key] = value;
    final next = AppConfig.fromJson(normalizeDraft(draft));
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(next);
    ref.invalidate(configProvider);
    // 主题即时生效
    if (key == 'GUI_THEME') {
      ref.read(themeModeProvider.notifier).state =
          value == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final t = AppThemeExt.of(context);

    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('配置加载失败: $e')),
      data: (cfg) {
        final draft = {...cfg.toJson()};
        void onSave(String key, dynamic value) => _saveKey(draft, key, value);
        _syncSources(cfg.additionalSources);

        List<SettingField> cat(String c) =>
            settingsFields.where((f) => f.category.startsWith(c)).toList();

        return LayoutBuilder(
          builder: (ctx, constraints) {
            final maxW = constraints.maxWidth > 860 ? 820.0 : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('设置',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800, color: t.text)),
                      const SizedBox(height: 16),
                      sectionCard(
                        context,
                        title: 'GitHub 推送（独立 cf-ip 仓库）',
                        icon: Icons.cloud_upload_outlined,
                        trailing: pill(context,
                            cfg.githubToken.isEmpty ? '未配置 Token' : '已配置',
                            cfg.githubToken.isEmpty ? t.warning.withValues(alpha: 0.15) : t.success.withValues(alpha: 0.15),
                            cfg.githubToken.isEmpty ? t.warning : t.success),
                        child: FieldList(
                          fields: cat('4. GitHub 推送'),
                          draft: draft,
                          onSave: onSave,
                        ),
                      ),
                      const SizedBox(height: 16),
                      sectionCard(
                        context,
                        title: '外观',
                        icon: Icons.palette_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FieldList(
                              fields: cat('5. 外观'),
                              draft: draft,
                              onSave: onSave,
                            ),
                            const SizedBox(height: 4),
                            Text('切换后立即生效；也可点击左侧底部的主题按钮快速切换。',
                                style: TextStyle(fontSize: 11, color: t.textDim)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      sectionCard(
                        context,
                        title: '附加数据源（${cfg.additionalSources.length}）',
                        icon: Icons.source,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('订阅转换会拉取以下节点池源并合并去重（URL + 启停 + 增删）。',
                                style: TextStyle(fontSize: 12, color: t.textDim)),
                            const SizedBox(height: 12),
                            for (var i = 0; i < cfg.additionalSources.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        cfg.additionalSources[i].enabled
                                            ? Icons.toggle_on
                                            : Icons.toggle_off,
                                        color: cfg.additionalSources[i].enabled
                                            ? t.primary
                                            : t.textDim,
                                      ),
                                      tooltip: cfg.additionalSources[i].enabled ? '已启用' : '已停用',
                                      onPressed: () {
                                        final list = [...cfg.additionalSources];
                                        final e = list[i];
                                        list[i] = SourceConfig(url: e.url, enabled: !e.enabled);
                                        onSave('ADDITIONAL_SOURCES',
                                            list.map((s) => s.toJson()).toList());
                                      },
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _srcCtl[i],
                                        onChanged: (v) {
                                          final list = [...cfg.additionalSources];
                                          list[i] = SourceConfig(url: v.trim(), enabled: list[i].enabled);
                                          onSave('ADDITIONAL_SOURCES',
                                              list.map((s) => s.toJson()).toList());
                                        },
                                        style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
                                        decoration: const InputDecoration(),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      tooltip: '删除',
                                      onPressed: () {
                                        final list = [...cfg.additionalSources]..removeAt(i);
                                        onSave('ADDITIONAL_SOURCES',
                                            list.map((s) => s.toJson()).toList());
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加数据源'),
                                  onPressed: () {
                                    final list = [...cfg.additionalSources,
                                        const SourceConfig(url: '')];
                                    onSave('ADDITIONAL_SOURCES',
                                        list.map((s) => s.toJson()).toList());
                                  },
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.restore),
                                  label: const Text('恢复为默认数据源'),
                                  onPressed: () {
                                    onSave('ADDITIONAL_SOURCES', defaultAdditionalSources
                                        .map((s) => s.toJson())
                                        .toList());
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      sectionCard(
                        context,
                        title: '关于',
                        icon: Icons.info_outline,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    gradient: t.primaryGradient(),
                                  ),
                                  child: const Icon(Icons.cloud, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Text('CF优选工具',
                                    style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
                                const SizedBox(width: 10),
                                pill(context, 'v1.0.0+1', t.surfaceHover, t.textDim),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('Cloudflare 边缘节点优选工具：订阅转换 → 延迟优选 → 推送 GitHub。',
                                style: TextStyle(fontSize: 12, color: t.textDim)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}