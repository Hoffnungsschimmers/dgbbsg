import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../widgets/common.dart';

/// 结果页的「原始内容」视图：整份结果文本可直接编辑，切回解析视图时由调用方校验落盘。
/// 从 `results_tab.dart` 迁出；控制器仍归调用方持有，`onChanged` 用于触发父级重建
/// （「全部复制」按钮的可用态依赖它）。
class ResultRawView extends StatelessWidget {
  const ResultRawView({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return card(
      context,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: t.textDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '编辑原始内容（修改后切回解析视图自动保存）',
                  style: TextStyle(color: t.textDim, fontSize: 13),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('全部复制', style: TextStyle(fontSize: 13)),
                onPressed: controller.text.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(
                          ClipboardData(text: controller.text),
                        );
                        AppToast.show(context, '已复制全部内容');
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
              minHeight: 200,
            ),
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              maxLines: null,
              expands: true,
              style: const TextStyle(
                fontFamily: 'AppMono',
                fontSize: 13,
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText:
                    '每行一个节点，如：\n1.2.3.4:443#精品v4 1\n[2606:4700:52::1]:443#精品v6 1',
                hintStyle: TextStyle(
                  color: t.textDim.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: t.radius),
                filled: true,
                fillColor: t.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
