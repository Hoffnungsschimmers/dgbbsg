import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/net/ip.dart';

// ═══════════════════════════════════════════════════════
// 国家分布小卡片（ResultsTab / GithubSyncTab 共用）
// ═══════════════════════════════════════════════════════

class GeoChip extends StatelessWidget {
  final String code;
  final int count;
  const GeoChip({required this.code, required this.count, super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final flag = countryCodeToFlag(code);
    final name = countryCodeToName(code);
    final display = code == '未知' ? '未知' : '$flag $name';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(display, style: TextStyle(fontSize: 14, color: t.text, fontFamily: 'AppMono')),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.edgeOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.edgeOrange)),
          ),
        ],
      ),
    );
  }
}
