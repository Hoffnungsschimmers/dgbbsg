import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/logging/app_logger.dart';

/// 卡片容器。
Widget card(BuildContext context, {required Widget child, EdgeInsets? padding}) {
  final t = AppThemeExt.of(context);
  return Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.radius,
      border: Border.all(color: t.border),
    ),
    child: child,
  );
}

/// 带头部（图标 + 标题 + 尾部动作）的分组卡片。
Widget sectionCard(
  BuildContext context, {
  required String title,
  IconData? icon,
  Widget? trailing,
  EdgeInsets? padding,
  EdgeInsets? margin,
  required Widget child,
}) {
  final t = AppThemeExt.of(context);
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      color: t.surface,
      borderRadius: t.radius,
      border: Border.all(color: t.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: t.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        Divider(height: 1, color: t.border),
        Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ],
    ),
  );
}

/// 状态药丸。
Widget pill(BuildContext context, String text, Color bg, Color fg) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// 空态占位。
Widget emptyState(BuildContext context, {required IconData icon, required String title, String? hint}) {
  final t = AppThemeExt.of(context);
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 44, color: t.textDim.withValues(alpha: 0.6)),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.text)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: t.textDim)),
        ],
      ],
    ),
  );
}

/// 三态按钮（主 / 次 / 危险），支持加载态。
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool loading;
  final IconData? icon;
  const AppButton(this.label,
      {this.onPressed, this.primary = true, this.danger = false, this.loading = false, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final enabled = onPressed != null && !loading;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary || danger ? Colors.white : t.primary,
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: 8),
        ],
        Text(label),
      ],
    );

    if (danger) {
      return OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: t.danger,
          side: BorderSide(color: t.danger.withValues(alpha: 0.6)),
        ),
        child: child,
      );
    }
    if (primary) return FilledButton(onPressed: enabled ? onPressed : null, child: child);
    return OutlinedButton(onPressed: enabled ? onPressed : null, child: child);
  }
}

/// 区块标题。
Widget sectionTitle(BuildContext context, String text) {
  final t = AppThemeExt.of(context);
  return Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: t.textDim),
  );
}

/// 单一强调色进度条。
Widget appProgress(BuildContext context, {double? value}) {
  final t = AppThemeExt.of(context);
  return LinearProgressIndicator(
    value: value,
    backgroundColor: t.primary.withValues(alpha: 0.14),
    color: t.primary,
    minHeight: 6,
    borderRadius: BorderRadius.circular(999),
  );
}

/// ────────────────────────── 表单行 ──────────────────────────

/// 开关行（label + Switch）。
Widget switchRow(BuildContext context, String label, bool value, ValueChanged<bool> onChanged, {String? hint}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: t.text)),
          ),
          Switch(
            value: value,
            activeThumbColor: t.primary,
            onChanged: onChanged,
          ),
        ],
      ),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(hint, style: TextStyle(fontSize: 11, color: t.textDim)),
        ),
    ],
  );
}

/// 滑块行（整数）。
Widget sliderRowInt(BuildContext context, String label, int value, int min, int max,
    ValueChanged<int> onChanged, {String suffix = ''}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: t.text))),
          Text('$value$suffix',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.primary)),
        ],
      ),
      Slider(
        value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: (max - min).clamp(1, 1000),
        activeColor: t.primary,
        onChanged: (v) => onChanged(v.round()),
      ),
    ],
  );
}

/// 滑块行（浮点，保留 1 位小数）。
Widget sliderRowDouble(BuildContext context, String label, double value, double min, double max,
    ValueChanged<double> onChanged, {String suffix = ''}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: t.text))),
          Text('${value.toStringAsFixed(1)}$suffix',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.primary)),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: (((max - min) * 10).round()).clamp(1, 1000),
        activeColor: t.primary,
        onChanged: onChanged,
      ),
    ],
  );
}

/// 文本输入行（label 在上）。
Widget textRow(BuildContext context, String label, TextEditingController ctl, ValueChanged<String> onChanged,
    {bool obscure = false, bool mono = true, String? hint}) {
  final t = AppThemeExt.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label.isNotEmpty) ...[
        Text(label, style: TextStyle(fontSize: 12, color: t.textDim)),
        const SizedBox(height: 4),
      ],
      TextField(
        controller: ctl,
        onChanged: onChanged,
        obscureText: obscure,
        style: TextStyle(fontFamily: mono ? 'Consolas' : null, fontSize: 13, color: t.text),
        decoration: InputDecoration(hintText: hint),
      ),
    ],
  );
}

/// 统计指标卡。
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color;
  final String? hint;
  const StatCard(this.title, this.value, this.icon, {this.color, this.hint, super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final c = color ?? t.primary;
    final h = hint;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radius,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 11, color: t.textDim)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.text)),
                ),
                if (h != null)
                  Text(h, style: TextStyle(fontSize: 10, color: t.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 步骤条（用于仪表盘的流水线阶段指示）。
class StepDots extends StatelessWidget {
  final List<String> steps;
  final int current; // -1 未开始
  const StepDots({required this.steps, this.current = -1, super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Container(
              width: 18,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: i <= current ? t.primary : t.border,
            ),
          _Step(
            label: steps[i],
            state: i < current
                ? _StepState.done
                : (i == current ? _StepState.active : _StepState.todo),
          ),
        ],
      ],
    );
  }
}

enum _StepState { todo, active, done }

class _Step extends StatelessWidget {
  final String label;
  final _StepState state;
  const _Step({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final Color color;
    final IconData? icon;
    switch (state) {
      case _StepState.done:
        color = t.primary;
        icon = Icons.check;
        break;
      case _StepState.active:
        color = t.info;
        icon = null;
        break;
      case _StepState.todo:
        color = t.border;
        icon = null;
        break;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state == _StepState.active ? color : t.surface,
            border: Border.all(color: color, width: state == _StepState.done ? 0 : 1.4),
          ),
          child: icon != null
              ? Icon(icon, size: 14, color: Colors.white)
              : (state == _StepState.active
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ))
                  : null),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: state == _StepState.active ? FontWeight.w700 : FontWeight.w500,
              color: state == _StepState.todo ? t.textDim : t.text,
            )),
      ],
    );
  }
}

/// 静态文本查看器：等宽字体整段可选中，支持「复制全部」。
class RawTextView extends StatelessWidget {
  final String text;
  final String? copyTooltip;
  final EdgeInsets padding;
  const RawTextView(this.text, {this.copyTooltip, this.padding = const EdgeInsets.all(0), super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Stack(
      children: [
        SelectionArea(
          child: SingleChildScrollView(
            padding: padding,
            child: SelectableText(
              text,
              style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: t.text),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: copyTooltip ?? '复制全部',
            color: t.textDim,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 日志视图：订阅 AppLogger 流，节流批量刷新，支持全选/复制。
class LogView extends StatefulWidget {
  final AppLogger logger;
  final String? emptyHint;
  const LogView({required this.logger, this.emptyHint, super.key});
  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final List<String> _lines = [];
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    widget.logger.stream.listen((line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });
    });
    widget.logger.clearStream.listen((_) {
      _lines.clear();
      if (mounted) setState(() {});
    });
  }

  String get _all => _lines.join('\n');

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final child = _lines.isEmpty
        ? Container(
            alignment: Alignment.center,
            child: Text(widget.emptyHint ?? '暂无日志', style: TextStyle(color: t.textDim, fontSize: 12)),
          )
        : SelectionArea(
            child: SingleChildScrollView(
              controller: _sc,
              padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
              child: SelectableText(
                _all,
                style: TextStyle(fontFamily: 'Consolas', fontSize: 12, height: 1.5, color: t.logFg),
              ),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制全部',
                  color: t.textDim,
                  onPressed: _lines.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _all));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制全部日志'), duration: Duration(seconds: 1)),
                          );
                        },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: '清空',
                  color: t.textDim,
                  onPressed: _lines.isEmpty
                      ? null
                      : () {
                          widget.logger.clear();
                        },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}