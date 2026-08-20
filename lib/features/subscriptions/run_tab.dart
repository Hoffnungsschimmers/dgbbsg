import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'subscriptions_state.dart';

class RunTab extends ConsumerStatefulWidget {
  const RunTab({super.key});
  @override
  ConsumerState<RunTab> createState() => _RunTabState();
}

class _RunTabState extends ConsumerState<RunTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _buildAutoUpdateIndicator() {
    final cfgAsync = ref.watch(configProvider);
    return cfgAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (cfg) {
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    final t = AppThemeExt.of(context);

    final isSubRunning = run.running && run.currentAction == RunAction.subscription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- 操作区 ----
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // 订阅IP
              if (isSubRunning)
                FilledButton.icon(
                  onPressed: null,
                  icon: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                  label: const Text('订阅中…'),
                )
              else
                AppButton('获取订阅', icon: Icons.cloud_download,
                    onPressed: () => ref.read(subProvider.notifier).runSubscription()),

              // 强制停止
              if (run.running)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: t.danger, side: BorderSide(color: t.danger)),
                  onPressed: () => ref.read(subProvider.notifier).cancel(),
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('强制停止'),
                ),
            ],
          ),
        ),

        // ---- 订阅转换进度卡 ----
        if (isSubRunning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: card(context, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.edgeOrange)),
                  const SizedBox(width: 12),
                  Text('正在抓取订阅并转换节点…', style: TextStyle(fontSize: 13, color: t.text)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(minHeight: 4,
                    backgroundColor: AppTheme.edgeOrange.withValues(alpha: 0.12),
                  ),
                ),
              ],
            )),
          ),
          const SizedBox(height: 8),
        ],

        // ---- 自动更新状态指示 ----
        _buildAutoUpdateIndicator(),

        // ---- 日志区 ----
        Expanded(child: LogView(logger: subLogger, emptyHint: '点击「获取订阅」开始')),
      ],
    );
  }
}
