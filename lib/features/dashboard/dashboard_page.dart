import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../features/results/result_state.dart';
import '../../features/widgets/common.dart';
import '../subscriptions/subscriptions_state.dart';

/// 工作台：一键顺序执行 + 阶段进度 + 实时日志 + 最新结果预览。
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});
  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  // -1 空闲；0 订阅转换；1 延迟优选；2 推送 GitHub
  int _phase = -1;
  bool _logCollapsed = false;
  bool _refreshing = false;

  Future<void> _runSubscription() async {
    setState(() => _phase = 0);
    await ref.read(subProvider.notifier).runSubscription();
    if (mounted) setState(() => _phase = _phase == 0 ? -1 : _phase);
  }

  Future<void> _runLatency() async {
    setState(() => _phase = 1);
    await ref.read(subProvider.notifier).runLatency();
    if (mounted) setState(() => _phase = _phase == 1 ? -1 : _phase);
  }

  Future<void> _runAll() async {
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null || _phase != -1) return;
    final logger = ref.read(subLoggerProvider);
    setState(() => _phase = 0);
    try {
      // 1) 订阅转换
      await ref.read(subProvider.notifier).runSubscription();
      // 2) 延迟优选（转换可开关，若被关闭则直接跳过）
      if (cfg.subConvertEnabled) {
        setState(() => _phase = 1);
        await ref.read(subProvider.notifier).runLatency();
      }
      // 3) 推送 GitHub（有 token 且有产物才推送）
      final topFile = cfg.subLatencyOutputFile;
      if (cfg.githubToken.isNotEmpty) {
        setState(() => _phase = 2);
        final (ok, _, msg) = await ref.read(subProvider.notifier).pushFile(topFile);
        logger.info(msg);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ));
      } else {
        logger.info('未配置 GitHub Token，跳过推送');
      }
    } finally {
      if (mounted) setState(() => _phase = -1);
    }
  }

  Future<void> _refreshResults() async {
    final cfg = ref.read(configProvider).valueOrNull;
    if (cfg == null) return;
    setState(() => _refreshing = true);
    try {
      final f = File(cfg.subLatencyOutputFile);
      await ref
          .read(resultProvider.notifier)
          .loadFile(f.existsSync() ? cfg.subLatencyOutputFile : cfg.subOutputFile);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final result = ref.watch(resultProvider);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth > 1200 ? 1160.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: cfgAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('配置加载失败: $e')),
                data: (cfg) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, cfg),
                    const SizedBox(height: 18),
                    _hero(context, cfg),
                    const SizedBox(height: 18),
                    _actionRow(context, cfg, result),
                    const SizedBox(height: 18),
                    _logCard(context),
                    const SizedBox(height: 18),
                    _previewCard(context, cfg, result),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('工作台',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: t.text,
                  height: 1.1,
                )),
            const SizedBox(height: 4),
            Text('一键优选 Cloudflare 边缘节点：订阅转换 → 延迟优选 → 推送 GitHub',
                style: TextStyle(fontSize: 12.5, color: t.textDim)),
          ],
        ),
        const Spacer(),
        IconButton.filledTonal(
          icon: _refreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: '刷新结果',
          onPressed: _refreshing ? null : _refreshResults,
        ),
      ],
    );
  }

  /// Hero：一键顺序执行 + 阶段 stepper。
  Widget _hero(BuildContext context, AppConfig cfg) {
    final t = AppThemeExt.of(context);
    final busy = _phase != -1;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: t.primaryGradient(),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepDots(
            steps: const ['订阅转换', '延迟优选', '推送 GitHub'],
            current: busy ? _phase : -1,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(busy ? '正在执行…' : '就绪',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 3),
                    Text(
                      busy
                          ? const ['订阅IP转换', '延迟优选测试', '推送 GitHub'][_phase]
                          : '依次执行：拉取订阅 → 测延迟/带宽 → 推送最优节点到 cf-ip 仓库',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: t.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: busy ? null : _runAll,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D9488)),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(busy ? '执行中…' : '顺序执行全部',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 三个行动卡：订阅IP / 延迟优选 / 推送 GitHub。
  Widget _actionRow(BuildContext context, AppConfig cfg, ResultState result) {
    final shown = result.rows.length;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
            _actionCard(
              context,
              icon: Icons.cloud_download_outlined,
              title: '订阅IP',
              desc: '拉取订阅源并转换节点 → ${cfg.subOutputFile}',
              value: '${cfg.subGenerators.length} 个订阅源',
              running: _phase == 0,
              onTap: _phase == -1 ? _runSubscription : null,
            ),
            _actionCard(
              context,
              icon: Icons.speed,
              title: '延迟优选',
              desc: '延迟/带宽测试，按质量分保留前 ${cfg.subLatencyTopN > 0 ? cfg.subLatencyTopN : '全部'} 名',
              value: '→ ${cfg.subLatencyOutputFile}',
              running: _phase == 1,
              onTap: _phase == -1 ? _runLatency : null,
            ),
            _actionCard(
              context,
              icon: Icons.cloud_upload_outlined,
              title: '推送 GitHub',
              desc: '将优选结果推送到 ${cfg.githubRepo}',
              value: cfg.githubToken.isEmpty ? '未配置 Token' : '已配置',
              running: _phase == 2,
              onTap: _phase == -1
                  ? () async {
                      final (ok, _, msg) = await ref
                          .read(subProvider.notifier)
                          .pushFile(cfg.subLatencyOutputFile);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(msg),
                          backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                        ));
                    }
                  : null,
            ),
            if (shown > 0)
              SizedBox(
                width: 220,
                child: StatCard('已加载结果', '$shown 条', Icons.storage, hint: '来自 ${result.sourceLabel ?? '—'}'),
              ),
          ],
    );
  }

  Widget _actionCard(BuildContext context,
      {required IconData icon,
      required String title,
      required String desc,
      required String value,
      required bool running,
      VoidCallback? onTap}) {
    final t = AppThemeExt.of(context);
    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radius,
        border: Border.all(color: running ? t.primary : t.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: t.radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (running ? t.primary : t.primarySoft),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: running
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(icon, color: t.primary, size: 20),
                ),
                const Spacer(),
                Text(value,
                    style: TextStyle(fontSize: 11, color: t.textDim, fontFamily: 'Consolas')),
              ],
            ),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
            const SizedBox(height: 4),
            Text(desc, style: TextStyle(fontSize: 12, color: t.textDim, height: 1.4)),
            const SizedBox(height: 10),
            Text(running ? '运行中…' : (onTap != null ? '点击执行 →' : ''),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.primary)),
          ],
        ),
      ),
    );
  }

  /// 运行日志（可折叠，内嵌）。
  Widget _logCard(BuildContext context) {
    final t = AppThemeExt.of(context);
    final logger = ref.watch(subLoggerProvider);
    return Container(
      decoration: BoxDecoration(
        color: t.logBg,
        borderRadius: t.radius,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _logCollapsed = !_logCollapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _phase != -1 ? t.success : t.textDim.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('运行日志',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, color: t.logFg)),
                  const Spacer(),
                  Icon(
                    _logCollapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                    color: t.logFg.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          if (!_logCollapsed)
            SizedBox(
              height: 220,
              child: LogView(logger: logger, emptyHint: '尚未运行，点击上方按钮或「顺序执行全部」开始'),
            ),
        ],
      ),
    );
  }

  /// 最新结果 Top10 预览。
  Widget _previewCard(BuildContext context, AppConfig cfg, ResultState result) {
    final t = AppThemeExt.of(context);
    final rows = result.rows;
    return sectionCard(
      context,
      title: '最新优选结果',
      icon: Icons.leaderboard_outlined,
      trailing: TextButton.icon(
        icon: const Icon(Icons.arrow_forward, size: 16),
        label: const Text('查看完整结果'),
        onPressed: () => ref.read(pageProvider.notifier).state = PageKey.results,
      ),
      padding: EdgeInsets.zero,
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: emptyState(context,
                  icon: Icons.inbox_outlined,
                  title: '暂无结果',
                  hint: '运行「顺序执行全部」或「订阅IP / 延迟优选」后，最优节点会显示在这里'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 表头
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      _th(context, '#', 0.5),
                      _th(context, '节点', 3.2),
                      _th(context, '带宽', 1.6),
                      _th(context, '延迟', 1.2),
                      _th(context, '国家', 0.8),
                    ],
                  ),
                ),
                Divider(height: 1, color: t.border),
                for (var i = 0; i < rows.length && i < 10; i++)
                  _previewRow(context, i, rows[i]),
              ],
            ),
    );
  }

  Widget _th(BuildContext context, String s, double flex) {
    final t = AppThemeExt.of(context);
    return Expanded(
      flex: flex.toInt(),
      child: Text(s,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: t.textDim)),
    );
  }

  Widget _previewRow(BuildContext context, int rank, ResultRow r) {
    final t = AppThemeExt.of(context);
    final speed = _num(r.speed);
    final latency = _num(r.latency);
    final best = _bestSpeedAcross(ref.read(resultProvider).rows);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: rank.isEven ? t.surface : t.surfaceHover.withValues(alpha: 0.4),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${rank + 1}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: rank < 3 ? t.primary : t.textDim)),
          ),
          Expanded(
            flex: 3,
            child: Text(r.node,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Consolas', fontSize: 12)),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: best == null || speed == null ? 0 : (speed / best).clamp(0.03, 1.0),
                      minHeight: 7,
                      backgroundColor: t.border.withValues(alpha: 0.5),
                      color: _speedColor(t, speed),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: Text(r.speed ?? '—',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 11.5)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(r.latency ?? '—',
                style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11.5,
                    color: latency == null ? t.textDim : _latencyColor(t, latency))),
          ),
          Expanded(
            flex: 1,
            child: Text(r.country.isEmpty ? '—' : r.country,
                style: TextStyle(fontSize: 11.5, color: t.textDim)),
          ),
        ],
      ),
    );
  }

  double? _num(String? s) {
    if (s == null) return null;
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  double? _bestSpeedAcross(List<ResultRow> rows) {
    double? best;
    for (final r in rows) {
      final v = _num(r.speed);
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  Color _speedColor(AppThemeExt t, double? v) {
    if (v == null) return t.border;
    if (v >= 100) return t.success;
    if (v >= 30) return t.primary;
    return t.warning;
  }

  Color _latencyColor(AppThemeExt t, double? v) {
    if (v == null) return t.textDim;
    if (v <= 120) return t.success;
    if (v <= 250) return t.warning;
    return t.danger;
  }
}