import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 统一输入框（带标签 + 等宽字体）。
Widget labeledTextField(
  BuildContext context,
  String label,
  TextEditingController ctl,
  ValueChanged<String> onChanged, {
  bool obscure = false,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: t.textDim)),
      const SizedBox(height: 4),
      TextField(
        controller: ctl,
        onChanged: onChanged,
        obscureText: obscure,
        style: const TextStyle(fontFamily: 'AppMono', fontSize: 14),
        decoration: inputDecorationFor(context),
      ),
    ],
  );
}

/// 统一开关行。
Widget labeledSwitch(BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
  final t = AppThemeExt.of(context);
  return Row(
    children: [
      Expanded(child: Text(label, style: TextStyle(color: t.text))),
      Switch(value: value, activeThumbColor: AppTheme.edgeOrange, onChanged: onChanged),
    ],
  );
}

/// 统一输入框装饰（与 ThemeData.inputDecorationTheme 保持一致）。
InputDecoration inputDecorationFor(BuildContext context) {
  final t = AppThemeExt.of(context);
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: t.bg,
    border: OutlineInputBorder(borderRadius: t.radius, borderSide: BorderSide(color: t.border)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}
