import 'package:flutter/material.dart';

import '../../app/motion.dart';

/// 数字滚动文本：值变化时 tween 动画。
class CountUpText extends StatefulWidget {
  final num value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;
  final String? suffix;

  const CountUpText(
    this.value, {
    super.key,
    this.decimals = 0,
    this.style,
    this.duration = Motion.staggerDur,
    this.suffix,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> {
  double _prev = 0;

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _prev = old.value.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: _prev, end: widget.value.toDouble()),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final text = widget.decimals > 0
            ? v.toStringAsFixed(widget.decimals)
            : v.round().toString();
        return Text(
          widget.suffix != null ? '$text${widget.suffix}' : text,
          style: widget.style,
        );
      },
    );
  }
}
