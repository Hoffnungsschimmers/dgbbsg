import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../settings/settings_fields.dart';
import '../subscriptions/subscriptions_state.dart';
import '../widgets/common.dart';
import 'field_list.dart';

/// 优选配置：数据源 / 订阅转换 / 延迟优选 / 带宽测速 四组分页表单。
class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});
  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  int _group = 0;
  final List<TextEditingController> _genCtl = [];

  @override
  void dispose() {
    for (final c in _genCtl) {
      c.dispose();
    }
    super.dispose();
  }

  /// 订阅器行控制器同步（差异守护，防全选 bug）。
  void _syncGenCtl(List<String> generators) {
    while (_genCtl.length < generators.length) {
      _genCtl.add(TextEditingController());
    }
    while (_genCtl.length > generators.length) {
      _genCtl.removeLast().dispose();
    }
    for (var i = 0; i < generators.length; i++) {
      if (_genCtl[i].text != generators[i]) _genCtl[i].text = generators[i];
    }
  }

  static const _groups = [
    (Icons.hub_outlined, '数据源', '输入模式 · 订阅器 · 订阅链接'),
    (Icons.swap_horiz, '订阅转换', '主流程 · Host/UUID · 抓取重试 · 输出'),
    (Icons.speed, '延迟优选', '延迟阈值 · 并发 · 质量权重'),
    (Icons.network_check, '带宽测速', '测速范围 · 下载大小 · 参考值'),
  ];

  List<SettingField> _byKeys(List<String> keys) => [
        for (final k in keys)
          settingsFields.firstWhere((f) => f.key == k),
      ];

  List<SettingField> _cat(String c) =>
      settingsFields.where((f) => f.category.startsWith(c)).toList();

  List<SettingField> _fieldsFor(int g) {
    switch (g) {
      case 0:
        return _byKeys(const ['SUB_INPUT_MODE', 'SUB_URLS']);
      case 1:
        final exclude = const {'SUB_INPUT_MODE', 'SUB_GENERATORS', 'SUB_URLS'};
        return _cat('1. 订阅转换')
            .where((f) => !exclude.contains(f.key))
            .toList();
      case 2:
        return _cat('2. 延迟优选');
      case 3:
        return _cat('3. 带宽测速');
      default:
        return const [];
    }
  }

  Future<void> _saveKey(Map<String, dynamic> draft, String key, dynamic value) async {
    draft[key] = value;
    final next = AppConfig.fromJson(normalizeDraft(draft));
    final repo = await ref.read(configRepositoryProvider.future);
    await repo.save(next);
    ref.invalidate(configProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final run = ref.watch(subProvider);
    final t = AppThemeExt.of(context);

    return cfgAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('配置加载失败: $e')),
      data: (cfg) {
        final draft = {...cfg.toJson()};
        void onSave(String key, dynamic value) => _saveKey(draft, key, value);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左：分组导航
            Container(
              width: 208,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _groups.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _groupItem(context, i, _groups[i]),
                    ),
                  const Spacer(),
                  PillNote('配置修改自动保存', Icons.autorenew),
                ],
              ),
            ),
            VerticalDivider(width: 1, color: t.border),
            // 右：字段区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('优选配置',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: t.text)),
                              const SizedBox(height: 3),
                              Text(_groups[_group].$3,
                                  style: TextStyle(fontSize: 12, color: t.textDim)),
                            ],
                          ),
                          const Spacer(),
                          AppButton('订阅IP',
                              icon: Icons.cloud_download,
                              loading: run.running,
                              onPressed: run.running
                                  ? null
                                  : () => ref.read(subProvider.notifier).runSubscription()),
                          const SizedBox(width: 10),
                          AppButton('延迟优选',
                              icon: Icons.speed,
                              primary: false,
                              loading: run.running,
                              onPressed: run.running
                                  ? null
                                  : () => ref.read(subProvider.notifier).runLatency()),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_group == 0)
                        _dataSourceTab(context, cfg, draft, onSave)
                      else
                        card(
                          context,
                          child: FieldList(
                            fields: _fieldsFor(_group),
                            draft: draft,
                            onSave: onSave,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _groupItem(BuildContext context, int i, (IconData, String, String) g) {
    final t = AppThemeExt.of(context);
    final active = _group == i;
    return Material(
      color: active ? t.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _group = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(g.$1, size: 19, color: active ? t.primary : t.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.$2,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? t.text : t.text)),
                    Text(g.$3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: t.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 数据源分组：输入模式 + 订阅器(启停开关) + 订阅链接。
  Widget _dataSourceTab(BuildContext context, AppConfig cfg,
      Map<String, dynamic> draft, void Function(String, dynamic) onSave) {
    final t = AppThemeExt.of(context);
    final generators = ((draft['SUB_GENERATORS'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final disabled =
        ((draft['SUB_DISABLED_GENERATORS'] as List?) ?? const []).toSet();
    _syncGenCtl(generators);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionCard(
          context,
          title: '输入模式',
          icon: Icons.swap_horiz,
          child: FieldList(
            fields: _byKeys(const ['SUB_INPUT_MODE']),
            draft: draft,
            onSave: onSave,
          ),
        ),
        const SizedBox(height: 16),
        sectionCard(
          context,
          title: '候选订阅器',
          icon: Icons.hub_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < generators.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _genCtl[i],
                          onChanged: (v) {
                            final list = [...generators];
                            list[i] = v;
                            onSave('SUB_GENERATORS', list);
                          },
                          style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                          decoration: const InputDecoration(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          disabled.contains(_genName(generators[i]))
                              ? Icons.toggle_off
                              : Icons.toggle_on,
                          color: disabled.contains(_genName(generators[i]))
                              ? t.textDim
                              : t.primary,
                        ),
                        tooltip: disabled.contains(_genName(generators[i])) ? '已停用' : '已启用',
                        onPressed: () {
                          final name = _genName(generators[i]);
                          final set = {...disabled};
                          if (set.contains(name)) {
                            set.remove(name);
                          } else {
                            set.add(name);
                          }
                          onSave('SUB_DISABLED_GENERATORS', set.toList());
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: '删除',
                        onPressed: () {
                          onSave('SUB_GENERATORS', [...generators]..removeAt(i));
                        },
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('添加订阅器'),
                onPressed: () => onSave('SUB_GENERATORS', [...generators, '名称|域名']),
              ),
              const SizedBox(height: 4),
              Text('格式：名称|域名（可带端口），点击开关可临时停用单个订阅器',
                  style: TextStyle(fontSize: 11, color: t.textDim)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        sectionCard(
          context,
          title: '订阅链接',
          icon: Icons.link,
          child: FieldList(
            fields: _byKeys(const ['SUB_URLS']),
            draft: draft,
            onSave: onSave,
          ),
        ),
      ],
    );
  }

  String _genName(String entry) => entry.split('|').first.trim();
}

/// 底部小提示条。
class PillNote extends StatelessWidget {
  final String text;
  final IconData icon;
  const PillNote(this.text, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surfaceHover,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: t.textDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: t.textDim)),
          ),
        ],
      ),
    );
  }
}