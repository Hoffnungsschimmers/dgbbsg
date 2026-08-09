import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
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
  Timer? _resultDismissTimer;
  bool _showResult = false;
  LatencySummary? _lastShownResult;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 监听 lastResult 变化，在 listener 中处理副作用（而非 build()）
    ref.listenManual(subProvider, (prev, next) {
      if (!next.running && next.lastResult != null && next.lastResult != _lastShownResult) {
        _lastShownResult = next.lastResult;
        _showResult = true;
        _scheduleResultDismiss();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _resultDismissTimer?.cancel();
    super.dispose();
  }

  void _scheduleResultDismiss() {
    _resultDismissTimer?.cancel();
    _resultDismissTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showResult = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    final t = AppThemeExt.of(context);

    final isSubRunning = run.running && run.currentAction == RunAction.subscription;
    final isLatencyRunning = run.running && run.currentAction == RunAction.latency;
    final progress = run.progress;

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
              // ① 订阅IP
              if (isSubRunning)
                FilledButton.icon(
                  onPressed: null,
                  icon: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                  label: const Text('订阅中…'),
                )
              else if (isLatencyRunning)
                OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.cloud_download), label: const Text('① 订阅IP'))
              else
                AppButton('① 订阅IP', icon: Icons.cloud_download,
                    onPressed: () => ref.read(subProvider.notifier).runSubscription()),

              // ② TCP延迟
              if (isLatencyRunning && progress != null)
                _ProgressButton(progress: progress)
              else if (isLatencyRunning)
                OutlinedButton.icon(
                  onPressed: null,
                  icon: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  label: const Text('启动中…'),
                )
              else if (isSubRunning)
                OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.speed), label: const Text('② TCP延迟'))
              else
                AppButton('② TCP延迟', icon: Icons.speed, primary: false,
                    onPressed: () => ref.read(subProvider.notifier).runLatency()),

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

        // ---- 进度卡（运行中显示）----
        AnimatedSize(
          duration: Motion.durBase,
          curve: Motion.curveStandard,
          alignment: Alignment.topCenter,
          child: (isLatencyRunning && progress != null)
              ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _ProgressCard(progress: progress))
              : const SizedBox.shrink(),
        ),
        if (isLatencyRunning && progress != null) const SizedBox(height: 8),

        // ---- 完成摘要卡 ----
        AnimatedSize(
          duration: Motion.durBase,
          curve: Motion.curveStandard,
          alignment: Alignment.topCenter,
          child: (_showResult && _lastShownResult != null)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CompletionCard(result: _lastShownResult!, onDismiss: () => setState(() => _showResult = false))
                      .animate()
                      .fadeIn(duration: Motion.durBase, curve: Motion.curveStandard)
                      .slideY(begin: 0.15, end: 0, duration: Motion.durBase, curve: Motion.curveStandard),
                )
              : const SizedBox.shrink(),
        ),
        if (_showResult && _lastShownResult != null) const SizedBox(height: 8),

        // ---- 日志区 ----
        Expanded(child: LogView(logger: subLogger, emptyHint: '点击上方按钮开始运行')),
      ],
    );
  }
}

/// 进度按钮：percent + done/total。
class _ProgressButton extends StatelessWidget {
  final LatencyProgress progress;
  const _ProgressButton({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200, height: 40,
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress.percent,
              backgroundColor: AppTheme.edgeOrange.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(AppTheme.edgeOrange),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Text('${(progress.percent * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ]),
    );
  }
}

/// 进度详情卡。
class _ProgressCard extends StatelessWidget {
  final LatencyProgress progress;
  const _ProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return card(context, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('延迟测试', style: TextStyle(fontSize: 13, color: t.textDim, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${(progress.percent * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.edgeOrange)),
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('${progress.done}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: t.text)),
        Text(' / ', style: TextStyle(fontSize: 16, color: t.textDim)),
        Text('${progress.total}', style: TextStyle(fontSize: 16, color: t.textDim)),
        const Spacer(),
        _miniStat(context, '已连通', progress.connected, t.success),
        const SizedBox(width: 12),
        _miniStat(context, '已淘汰', progress.eliminated, t.danger),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress.percent, minHeight: 6,
            backgroundColor: AppTheme.edgeOrange.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(AppTheme.edgeOrange)),
      ),
    ]));
  }

  Widget _miniStat(BuildContext context, String label, int value, Color color) {
    final t = AppThemeExt.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
      Text('$value', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]);
  }
}

/// 完成摘要卡。
class _CompletionCard extends StatelessWidget {
  final LatencySummary result;
  final VoidCallback onDismiss;
  const _CompletionCard({required this.result, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return card(context, child: Row(children: [
      Container(width: 40, height: 40,
          decoration: BoxDecoration(color: t.success.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(Icons.check_circle, color: t.success, size: 24)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('延迟优选完成', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: t.text)),
        const SizedBox(height: 4),
        Row(children: [
          Text('测试 ${result.tested}', style: TextStyle(fontSize: 13, color: AppTheme.edgeOrange, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('连通 ${result.connected}', style: TextStyle(fontSize: 13, color: t.success, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('保留 ${result.kept}', style: TextStyle(fontSize: 13, color: t.text, fontWeight: FontWeight.w600)),
        ]),
      ])),
      IconButton(icon: Icon(Icons.close, size: 18, color: t.textDim), onPressed: onDismiss),
    ]));
  }
}
