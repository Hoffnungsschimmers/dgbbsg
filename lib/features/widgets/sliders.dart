import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'count_up_text.dart';

/// 带 count-up 的整数滑块。
Widget labeledSliderCountUp(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> onChanged, {
  String? suffix,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          CountUpText(
            value.round(),
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange),
            suffix: suffix,
          ),
        ],
      ),
      Slider(value: value, min: min, max: max, activeColor: AppTheme.edgeOrange, onChanged: onChanged),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${min.round()}', style: TextStyle(fontSize: 11, color: t.textDim)),
            Text('${max.round()}', style: TextStyle(fontSize: 11, color: t.textDim)),
          ],
        ),
      ),
    ],
  );
}

/// 带 count-up 的浮点滑块。
Widget labeledDoubleSliderCountUp(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  ValueChanged<double> onChanged, {
  String? suffix,
}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: t.text))),
          CountUpText(
            value,
            decimals: 2,
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.edgeOrange),
            suffix: suffix,
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: min == max ? null : ((max - min) * 100).round().clamp(1, 1 << 30),
        activeColor: AppTheme.edgeOrange,
        onChanged: onChanged,
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(min.toStringAsFixed(min == min.roundToDouble() ? 0 : 1), style: TextStyle(fontSize: 11, color: t.textDim)),
            Text(max.toStringAsFixed(max == max.roundToDouble() ? 0 : 1), style: TextStyle(fontSize: 11, color: t.textDim)),
          ],
        ),
      ),
    ],
  );
}
