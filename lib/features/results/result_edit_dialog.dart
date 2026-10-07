import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/endpoint.dart';
import '../widgets/common.dart';
import 'result_state.dart';

/// 编辑单个节点：拆成 `IP:端口` 与「来源 备注」两栏，国家码沿用原行的值。
/// 从 `results_tab.dart` 迁出；校验语义不变——非法地址弹提示且不落盘，
/// `updateRow` 抛出的 FormatException 也在这里转成 toast。
void showResultEditDialog(
  WidgetRef ref,
  BuildContext context, {
  required int originalIndex,
  required ResultRow row,
  required Future<void> Function() save,
}) {
  final ipPortCtl = TextEditingController(text: row.ipPort);
  final sourceCtl = TextEditingController(text: row.source);

  showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('编辑节点'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipPortCtl,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
              decoration: InputDecoration(
                labelText: 'IP:端口',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sourceCtl,
              style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
              decoration: InputDecoration(
                labelText: '来源',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final ipPort = ipPortCtl.text.trim();
              final source = sourceCtl.text.trim();
              if (ipPort.isNotEmpty) {
                final cc = nodeCountry(row.node);
                final ccPart = cc.isNotEmpty ? '#$cc' : '';
                final srcPart = source.isNotEmpty ? ' $source' : '';
                final newNode = '$ipPort$ccPart$srcPart';
                if (!validResultNode(newNode)) {
                  AppToast.show(ctx, '请输入有效的地址:端口', success: false);
                  return;
                }
                try {
                  ref
                      .read(resultProvider.notifier)
                      .updateRow(originalIndex, newNode);
                } on FormatException catch (e) {
                  AppToast.show(ctx, e.message, success: false);
                  return;
                }
                save();
              }
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}
