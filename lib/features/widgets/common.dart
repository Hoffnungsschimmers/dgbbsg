import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/motion.dart';
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

/// 状态药丸。根据背景色亮度自动选择文字颜色。
Widget pill(BuildContext context, String text, Color bg) {
  final fg = _contrastColor(bg, context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// 带图标的药丸（emoji/time 等场景替换为 Icon）。
Widget pillWithIcon(BuildContext context, {required IconData icon, required String text, required Color bg}) {
  final fg = _contrastColor(bg, context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
      ],
    ),
  );
}

/// 根据背景色亮度返回白色或主题正文色。
Color _contrastColor(Color bg, BuildContext context) {
  // 计算相对亮度（WCAG 公式）
  final luminance = bg.computeLuminance();
  return luminance > 0.4 ? AppThemeExt.of(context).text : Colors.white;
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;
  const AppButton(this.label, {this.onPressed, this.primary = true, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: 18),
        if (icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}

/// 区块标题。
Widget sectionTitle(BuildContext context, String text) {
  final t = AppThemeExt.of(context);
  return Text(
    text,
    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textDim),
  );
}


/// 日志视图：订阅 AppLogger 流，节流批量刷新，支持全选/复制。
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
            padding: EdgeInsets.only(right: 48) + padding,
            child: SelectableText(
              text,
              style: TextStyle(fontFamily: 'AppMono', fontSize: 13, color: t.text),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            decoration: BoxDecoration(
              color: t.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.border),
            ),
            child: IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: copyTooltip ?? '复制全部',
              color: t.textDim,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                AppToast.show(context, '已复制');
              },
            ),
          ),
        ),
      ],
    );
  }
}

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
  StreamSubscription<String>? _logSub;
  StreamSubscription<void>? _clearSub;

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    _logSub = widget.logger.stream.listen((line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });
    });
    _clearSub = widget.logger.clearStream.listen((_) {
      _lines.clear();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _clearSub?.cancel();
    _sc.dispose();
    super.dispose();
  }

  String get _all => _lines.join('\n');

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final child = _lines.isEmpty
        ? Container(
            alignment: Alignment.center,
            child: Text(widget.emptyHint ?? '暂无日志', style: TextStyle(color: t.textDim, fontSize: 13)),
          )
        : SelectionArea(
            child: SingleChildScrollView(
              controller: _sc,
              padding: const EdgeInsets.fromLTRB(8, 48, 48, 8),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    for (var i = 0; i < _lines.length; i++) ...[
                      if (i > 0) const TextSpan(text: '\n'),
                        TextSpan(
                        text: _lines[i],
                        style: TextStyle(
                          fontFamily: 'AppMono',
                          fontSize: 13,
                          color: _lines[i].startsWith('[错误]')
                              ? t.danger
                              : _lines[i].startsWith('[警告]')
                                  ? t.warning
                                  : _lines[i].startsWith('[成功]')
                                      ? t.success
                                      : t.logFg,
                          fontWeight: _lines[i].startsWith('[错误]') ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        // 固定右上角操作按钮
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
                          AppToast.show(context, '已复制全部日志');
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

// ═══════════════════════════════════════════════════════
// 增强组件：折叠分区 / 数字滚动 / Toast
// ═══════════════════════════════════════════════════════

/// 可折叠分区（带 chevron 旋转动效）。
class SectionCollapsible extends StatefulWidget {
  final String title;
  final IconData? icon;
  final bool initiallyExpanded;
  final Widget child;
  const SectionCollapsible({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.initiallyExpanded = true,
  });

  @override
  State<SectionCollapsible> createState() => _SectionCollapsibleState();
}

class _SectionCollapsibleState extends State<SectionCollapsible>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _chevronCtrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _chevronCtrl = AnimationController(
      vsync: this,
      duration: Motion.durFast,
      value: _expanded ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _chevronCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _chevronCtrl.forward();
      } else {
        _chevronCtrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.radius,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: t.radius,
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 16, color: AppTheme.edgeOrange),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: t.textDim),
                    ),
                  ),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_chevronCtrl),
                    child: Icon(Icons.expand_more, color: t.textDim, size: 20),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.durBase,
            curve: Motion.curveStandard,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(height: 1, color: t.border),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: widget.child,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

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

/// 轻量应用内 Toast（OverlayEntry + AnimatedSwitcher）。
/// 使用：AppToast.show(context, '消息', success: true);
class AppToast {
  static OverlayEntry? _current;

  static void show(
    BuildContext context,
    String message, {
    bool success = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    _current?.remove();
    _current = null;

    final t = AppThemeExt.of(context);
    final bg = success ? t.success : t.danger;
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        bg: bg,
        icon: icon,
        onDismiss: () {
          entry.remove();
          if (_current == entry) _current = null;
        },
        duration: duration,
      ),
    );
    _current = entry;
    Overlay.of(context).insert(entry);
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Color bg;
  final IconData icon;
  final VoidCallback onDismiss;
  final Duration duration;
  const _ToastWidget({
    required this.message,
    required this.bg,
    required this.icon,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Motion.durBase);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard);
    _offset = Tween(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Motion.curveStandard));
    // 进场动画
    _ctrl.forward();
    // 自动消失
    _dismissTimer = Timer(widget.duration, () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏（NavigationRail）时用固定底部偏移，窄屏（NavigationBar）时加上导航栏高度
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final isWide = MediaQuery.sizeOf(context).width >= 720;
    final bottom = viewPadding.bottom + (isWide ? 16.0 : kBottomNavigationBarHeight + 8);
    return Positioned(
      bottom: bottom,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _offset,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: widget.bg,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: widget.bg.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
