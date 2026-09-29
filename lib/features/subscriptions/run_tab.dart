import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../results/result_state.dart';
import '../widgets/common.dart';
import '../widgets/toast.dart';
import 'subscriptions_state.dart';

/// 运行页：订阅转换 + 落地检测 + 日志。
class RunTab extends ConsumerStatefulWidget {
  const RunTab({super.key});
  @override
  ConsumerState<RunTab> createState() => _RunTabState();
}

class _RunTabState extends ConsumerState<RunTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// 获取订阅，完成后用 Toast 汇总结果（成功节点数 / 结果文件）。
  Future<void> _runSubscriptionAndNotify() async {
    await ref.read(subProvider.notifier).runSubscription();
    if (!mounted) return;
    final st = ref.read(resultProvider);
    final count = st.rows.length;
    if (count > 0) {
      AppToast.show(context, '获取订阅完成：${st.sourceLabel ?? ''} 共 $count 个节点');
    } else {
      AppToast.show(context, '获取订阅完成：未解析到节点，详见日志', success: false);
    }
  }

  /// 落地检测：[useProxy] 为 true 表示开代理测落地，为 false 表示直连测落地。
  Future<void> _runLandingAndNotify(bool useProxy) async {
    final (ok, total) = await ref.read(subProvider.notifier).runLandingCheck(useProxy: useProxy);
    if (!mounted) return;
    if (total == 0) {
      AppToast.show(context, '落地检测：无可用节点，详见日志', success: false);
    } else if (ok == 0) {
      AppToast.show(context, '落地检测：$total 个 IP 均未识别，详见日志', success: false);
    } else {
      AppToast.show(context, '落地检测完成：$ok/$total 个 IP 已更新落地');
    }
  }

  Widget _buildAutoUpdateIndicator(AppConfig cfg) {
    if (!cfg.subAutoUpdateEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: pillWithIcon(
        context,
        icon: Icons.update,
        text: '自动更新：每 ${cfg.subAutoUpdateIntervalMin} 分钟',
        bg: AppTheme.edgeOrange.withValues(alpha: 0.12),
      ),
    );
  }

  /// 状态卡：运行中显示当前动作与停止按钮；空闲显示动作入口。
  /// 各动作互斥（[SubscriptionsNotifier] 保证同时只跑一个）。
  Widget _buildStatusCard(AppConfig cfg, SubscriptionsState run) {
    final t = AppThemeExt.of(context);
    final busy = run.running;
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final actionLabel = switch (run.currentAction) {
      RunAction.subscription => '正在获取订阅…',
      RunAction.landing => '正在检测落地…',
      null => '任务进行中…',
    };

    final statusIcon = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: busy ? t.accentSoft : t.surfaceHover,
        border: Border.all(color: busy ? t.accent : t.border, width: 2),
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accent),
            )
          : Icon(Icons.cloud_download_outlined, color: t.textDim, size: 24),
    );

    final statusText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          busy ? actionLabel : '就绪',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: t.text),
        ),
        const SizedBox(height: 6),
        Text(
          busy
              ? '任务进行中，可随时停止'
              : '先「获取订阅」生成节点，再用「测落地」识别每个 IP 的真实落地并覆盖国家码',
          style: TextStyle(fontSize: 12, color: t.textDim),
        ),
      ],
    );

    final action = busy
        ? OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: t.danger,
              side: BorderSide(color: t.danger.withValues(alpha: 0.6)),
            ),
            onPressed: () => ref.read(subProvider.notifier).cancel(),
            icon: const Icon(Icons.stop, size: 18),
            label: const Text('强制停止'),
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runLandingAndNotify(true),
                icon: const Tooltip(
                  message: '开代理后点此：经代理检测每个 IP 的落地',
                  child: Icon(Icons.public, size: 18),
                ),
                label: const Text('代理测落地'),
              ),
              OutlinedButton.icon(
                onPressed: () => _runLandingAndNotify(false),
                icon: const Tooltip(
                  message: '关代理后点此：直连检测当前网络的真实落地',
                  child: Icon(Icons.public_outlined, size: 18),
                ),
                label: const Text('直连测落地'),
              ),
              FilledButton.icon(
                onPressed: _runSubscriptionAndNotify,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('获取订阅'),
              ),
            ],
          );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.surface, t.accentSoft.withValues(alpha: 0.35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: t.radius,
        border: Border.all(color: busy ? t.accent.withValues(alpha: 0.4) : t.border),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    statusIcon,
                    const SizedBox(width: 16),
                    Expanded(child: statusText),
                  ],
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            )
          : Row(
              children: [
                statusIcon,
                const SizedBox(width: 16),
                Expanded(child: statusText),
                const SizedBox(width: 12),
                action,
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    final cfgAsync = ref.watch(configProvider);
    final t = AppThemeExt.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('运行',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: cfgAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (cfg) => _buildStatusCard(cfg, run),
          ),
        ),
        const SizedBox(height: 8),
        if (cfgAsync.value != null) _buildAutoUpdateIndicator(cfgAsync.value!),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('运行日志',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
        // 日志区（白底）
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border),
              ),
              child: LogView(logger: subLogger, emptyHint: '点击「获取订阅」开始'),
            ),
          ),
        ),
      ],
    );
  }
}