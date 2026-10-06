import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../widgets/common.dart';

/// 配置页订阅列表的条目控件：卡片、编辑弹窗、批量小标签、批量粘贴弹窗。
/// 从 `config_tab.dart` 原样迁出（仅把 State 的 `context` 改成显式参数），行为不变。

/// 列表项：静态卡片（备注 + 内容），点击整卡弹出编辑对话框。
/// 开关与删除保持行内大点击区域，编辑通过弹窗完成（避免行内小框难输入）。
Widget buildItemCard(
  BuildContext context, {
  required String note,
  required String value,
  required bool isEnabled,
  required VoidCallback onTapEdit,
  required VoidCallback onToggle,
  required VoidCallback onDelete,
}) {
  final t = AppThemeExt.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTapEdit,
        child: Ink(
          decoration: BoxDecoration(
            color: isEnabled ? t.surface : t.surfaceHover.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEnabled ? t.border : t.border.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              // 内联开关（点击区域大，方便快速切换）
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: Icon(
                    isEnabled ? Icons.toggle_on : Icons.toggle_off,
                    color: isEnabled ? AppTheme.edgeOrange : t.textDim,
                    size: 30,
                  ),
                ),
              ),
              // 备注 + 内容（静态显示，点击弹窗编辑）
              Expanded(
                child: InkWell(
                  onTap: onTapEdit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.isEmpty ? '（未命名）' : note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isEnabled ? t.text : t.textDim,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'AppMono',
                            fontSize: 12,
                            color: isEnabled ? t.textDim : t.textDim.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 删除按钮
              IconButton(
                icon: Icon(Icons.close, size: 18, color: t.textDim),
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 编辑/新增条目弹窗：备注 + 内容（订阅器另有密钥）双框全宽输入。
void showItemEditor(
  BuildContext context, {
  required String title,
  required String noteLabel,
  required String valueLabel,
  required void Function(String note, String value, String secret) onSave,
  String? note,
  String? value,
  String? secret,
  bool showSecret = false,
  String? secretLabel,
}) {
  final noteCtl = TextEditingController(text: note ?? '');
  final valueCtl = TextEditingController(text: value ?? '');
  final secretCtl = TextEditingController(text: secret ?? '');
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = AppThemeExt.of(ctx);
      return AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(noteLabel,
                  style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              TextField(
                key: const Key('editor_note'),
                controller: noteCtl,
                autofocus: true,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '备注（显示在列表中的名称）',
                  hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              Text(valueLabel,
                  style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              TextField(
                key: const Key('editor_value'),
                controller: valueCtl,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: valueLabel == '链接' ? 'https://…' : '域名',
                  hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              if (showSecret) ...[
                const SizedBox(height: 12),
                Text(secretLabel ?? '密钥（可选）',
                    style: TextStyle(fontSize: 12, color: t.textDim, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                TextField(
                  key: const Key('editor_secret'),
                  controller: secretCtl,
                  style: const TextStyle(fontFamily: 'AppMono', fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'edgetunnel 部署 uuid 或 token',
                    hintStyle: TextStyle(color: t.textDim.withValues(alpha: 0.5), fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = noteCtl.text.trim();
              final v = valueCtl.text.trim();
              final s = secretCtl.text.trim();
              if (v.isEmpty) {
                AppToast.show(ctx, '$valueLabel 不能为空', success: false);
                return;
              }
              onSave(n, v, s);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
}

/// 批量操作小标签按钮
Widget batchToggleChip(
  BuildContext context, {
  required String label,
  required bool active,
  required VoidCallback onTap,
}) {
  final t = AppThemeExt.of(context);
  return InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? AppTheme.edgeOrange.withValues(alpha: 0.15) : t.surfaceHover,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? AppTheme.edgeOrange.withValues(alpha: 0.3) : t.border),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: active ? AppTheme.edgeOrange : t.textDim)),
    ),
  );
}

/// 批量粘贴对话框
void showBatchPasteDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required void Function(List<String> lines) onConfirm,
}) {
  final ctl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = AppThemeExt.of(ctx);
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hint, style: TextStyle(fontSize: 13, color: t.textDim)),
              const SizedBox(height: 12),
              TextField(
                controller: ctl,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
                decoration: InputDecoration(
                  hintText: '在此粘贴，每行一个…',
                  hintStyle: TextStyle(color: t.textDim, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(12),
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final lines = ctl.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              if (lines.isNotEmpty) onConfirm(lines);
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      );
    },
  );
}
