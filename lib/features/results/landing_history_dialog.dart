import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/net/landing_history.dart';

/// 落地历史面板：IP → 历次落地观测（机场码/国家码/当时的出口 IP）。
/// 从 `results_tab.dart` 迁出，内容与排序行为不变。
class LandingHistoryDialog extends StatefulWidget {
  const LandingHistoryDialog({required this.history, super.key});

  final LandingHistory history;

  @override
  State<LandingHistoryDialog> createState() => _LandingHistoryDialogState();
}

class _LandingHistoryDialogState extends State<LandingHistoryDialog> {
  final _queryCtl = TextEditingController();

  @override
  void dispose() {
    _queryCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final q = _queryCtl.text.trim().toLowerCase();
    final ips =
        widget.history.keys
            .where((ip) => q.isEmpty || ip.toLowerCase().contains(q))
            .toList()
          ..sort();
    final width = (MediaQuery.sizeOf(context).width * 0.86).clamp(280.0, 560.0);

    return AlertDialog(
      title: const Text('落地历史'),
      content: SizedBox(
        width: width,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _queryCtl,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索 IP…',
                hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(borderRadius: t.radius),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ips.isEmpty
                  ? Center(
                      child: Text(
                        widget.history.isEmpty
                            ? '还没有落地记录：先在运行页点「测落地」。'
                            : '没有匹配的 IP。',
                        style: TextStyle(color: t.textDim, fontSize: 13),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final ip in ips)
                          ExpansionTile(
                            dense: true,
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              ip,
                              style: const TextStyle(
                                fontFamily: 'AppMono',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '当前 ${widget.history[ip]!.first.cc}'
                              ' · 记录了 ${widget.history[ip]!.length} 次变化',
                              style: TextStyle(fontSize: 11, color: t.textDim),
                            ),
                            children: [
                              for (final o in widget.history[ip]!)
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  title: Text(
                                    '${o.at}   ${o.colo.isEmpty ? '归属地' : o.colo} → ${o.cc}',
                                    style: const TextStyle(
                                      fontFamily: 'AppMono',
                                      fontSize: 12,
                                    ),
                                  ),
                                  subtitle: o.egressIp.isEmpty
                                      ? null
                                      : Text(
                                          '出口 ${o.egressIp}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: t.textDim,
                                          ),
                                        ),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
