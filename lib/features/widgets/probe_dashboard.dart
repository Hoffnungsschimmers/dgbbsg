import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import 'common.dart';

/// Real-time latency probe dashboard widget.
///
/// Displays a progress ring, live stats grid, and latency distribution bar
/// during a latency test run. All numbers animate smoothly via [CountUpText].
class ProbeDashboard extends StatelessWidget {
  final int done;
  final int total;
  final int connected;
  final int eliminated;
  final int connectedCount;
  final int eliminatedCount;

  const ProbeDashboard({
    super.key,
    required this.done,
    required this.total,
    required this.connected,
    required this.eliminated,
    required this.connectedCount,
    required this.eliminatedCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final percent = total == 0 ? 0.0 : done / total;

    return card(
      context,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Header ----
          Row(children: [
            Text('延迟探测仪表盘',
                style: TextStyle(fontSize: 13, color: t.textDim, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('实时', style: TextStyle(fontSize: 11, color: t.success, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            _PulsingDot(color: t.success),
          ]),
          const SizedBox(height: 12),

          // ---- Ring + Stats Row ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Progress Ring
              _ProgressRing(percent: percent, size: 72, strokeWidth: 6),
              const SizedBox(width: 16),
              // Stats Grid (2x2)
              Expanded(
                child: _StatsGrid(
                  done: done,
                  total: total,
                  connected: connected,
                  eliminated: eliminated,
                  percent: percent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- Distribution Bar: Connected vs Eliminated ----
          _DistributionBar(
            connected: connectedCount,
            eliminated: eliminatedCount,
          ),
        ],
      ),
    );
  }
}

/// Pulsing dot indicator for "live" status.
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Circular progress ring with percentage in center.
/// Tracks previous percent to animate smoothly without resetting to 0.
class _ProgressRing extends StatefulWidget {
  final double percent;
  final double size;
  final double strokeWidth;

  const _ProgressRing({
    required this.percent,
    required this.size,
    required this.strokeWidth,
  });

  @override
  State<_ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends State<_ProgressRing> {
  double _prevPercent = 0;

  @override
  void didUpdateWidget(covariant _ProgressRing old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent) {
      _prevPercent = old.percent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background ring
          SizedBox(
            width: widget.size, height: widget.size,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: widget.strokeWidth,
              color: t.border,
            ),
          ),
          // Foreground progress (animates from previous value)
          SizedBox(
            width: widget.size, height: widget.size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: _prevPercent, end: widget.percent),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: widget.strokeWidth,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppTheme.edgeOrange),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          // Center text
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUpText(
                (widget.percent * 100).round(),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: t.text),
                suffix: '%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 2x2 mini stat cards grid.
class _StatsGrid extends StatelessWidget {
  final int done;
  final int total;
  final int connected;
  final int eliminated;
  final double percent;

  const _StatsGrid({
    required this.done,
    required this.total,
    required this.connected,
    required this.eliminated,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: _MiniStatCard(
            label: '已测试',
            sublabel: '总数',
            value: done,
            subvalue: total,
            color: AppTheme.edgeOrange,
          )),
          const SizedBox(width: 8),
          Expanded(child: _MiniStatCard(
            label: '已连通',
            value: connected,
            color: t.success,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _MiniStatCard(
            label: '已淘汰',
            value: eliminated,
            color: t.danger,
          )),
          const SizedBox(width: 8),
          Expanded(child: _MiniStatCard(
            label: '当前进度',
            value: (percent * 100).round(),
            suffix: '%',
            color: AppTheme.edgeOrange,
          )),
        ]),
      ],
    );
  }
}

/// Single mini stat card with label and animated value.
class _MiniStatCard extends StatelessWidget {
  final String label;
  final String? sublabel;
  final int value;
  final int? subvalue;
  final Color color;
  final String? suffix;

  const _MiniStatCard({
    required this.label,
    this.sublabel,
    required this.value,
    this.subvalue,
    required this.color,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label,
                  style: TextStyle(fontSize: 11, color: t.textDim, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis)),
              if (sublabel != null) ...[
                const SizedBox(width: 4),
                Text(sublabel!,
                    style: TextStyle(fontSize: 10, color: t.textDim)),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              CountUpText(
                value,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                suffix: suffix,
              ),
              if (subvalue != null) ...[
                Text(' / ', style: TextStyle(fontSize: 11, color: t.textDim)),
                CountUpText(
                  subvalue!,
                  style: TextStyle(fontSize: 12, color: t.textDim),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Horizontal distribution bar showing connected (green) vs eliminated (red).
/// Uses [AnimatedContainer] for smooth width transitions.
class _DistributionBar extends StatelessWidget {
  final int connected;
  final int eliminated;

  const _DistributionBar({
    required this.connected,
    required this.eliminated,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final sum = connected + eliminated;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Legend row
        Row(children: [
          _legendDot(t.success),
          const SizedBox(width: 4),
          Text('已连通', style: TextStyle(fontSize: 10, color: t.textDim)),
          const SizedBox(width: 14),
          _legendDot(t.danger),
          const SizedBox(width: 4),
          Text('已淘汰', style: TextStyle(fontSize: 10, color: t.textDim)),
        ]),
        const SizedBox(height: 6),

        // Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: AnimatedContainer(
            duration: Motion.durBase,
            curve: Motion.curveStandard,
            height: 14,
            child: sum == 0
                ? Container(color: t.border)
                : Row(
                    children: [
                      if (connected > 0)
                        Expanded(
                          flex: connected,
                          child: _Segment(
                            color: t.success,
                            count: connected,
                          ),
                        ),
                      if (eliminated > 0)
                        Expanded(
                          flex: eliminated,
                          child: _Segment(
                            color: t.danger,
                            count: eliminated,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 4),

        // Count labels row
        Row(children: [
          _countLabel(connected, t.success),
          _countLabel(eliminated, t.danger),
        ]),
      ],
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _countLabel(int count, Color color) {
    return Expanded(
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// Single segment of the distribution bar.
class _Segment extends StatelessWidget {
  final Color color;
  final int count;

  const _Segment({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: Alignment.center,
      child: count >= 3
          ? Text(
              '$count',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
            )
          : const SizedBox.shrink(),
    );
  }
}
