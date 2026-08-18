import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'result_state.dart';

// ═══════════════════════════════════════════════════════
// 统计区（错峰入场动画）
// ═══════════════════════════════════════════════════════

class ResultStatsRow extends StatelessWidget {
  const ResultStatsRow({
    super.key,
    required this.rows,
    required this.geo,
    required this.lowestLatency,
  });

  final List<ResultRow> rows;
  final Map<String, int> geo;
  final double? lowestLatency;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _stat(context, '节点数', rows.length.toDouble(), Icons.storage, decimals: 0, index: 0),
        _stat(context, '国家/地区', geo.length.toDouble(), Icons.public, decimals: 0, index: 1),
        _stat(context, '最低延迟', lowestLatency ?? 0, Icons.timeline, decimals: 0, suffix: ' ms', index: 2),
      ],
    );
  }

  Widget _stat(BuildContext context, String title, num value, IconData icon, {int decimals = 0, String? suffix, int index = 0}) {
    final t = AppThemeExt.of(context);
    return SizedBox(
      width: 200,
      child: card(
        context,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.edgeOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.edgeOrange, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13, color: t.textDim)),
                  const SizedBox(height: 3),
                  CountUpText(
                    value,
                    decimals: decimals,
                    suffix: suffix,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate(delay: Motion.staggerDelay(index))
        .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
        .slideY(begin: 0.06, end: 0, duration: Motion.staggerDur, curve: Motion.curveStandard);
  }
}
