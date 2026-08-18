import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/logging/app_logger.dart';
import 'toast.dart';

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
  Timer? _flushTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    _logSub = widget.logger.stream.listen((String line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      _dirty = true;
      _scheduleFlush();
    });
    _clearSub = widget.logger.clearStream.listen((_) {
      _lines.clear();
      _dirty = true;
      _scheduleFlush();
    });
  }

  void _scheduleFlush() {
    _flushTimer ??= Timer(const Duration(milliseconds: 80), () {
      _flushTimer = null;
      if (_dirty && mounted) {
        _dirty = false;
        setState(() {});
        // 平滑滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _sc.hasClients) {
            _sc.animateTo(
              _sc.position.maxScrollExtent,
              duration: Motion.durFast,
              curve: Motion.curveStandard,
            );
          }
        });
      }
      if (_dirty) _scheduleFlush();
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal, size: 40, color: t.textDim.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                Text(
                  widget.emptyHint ?? '暂无日志',
                  style: TextStyle(color: t.textDim, fontSize: 13),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
                .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: Motion.staggerDur, curve: Motion.curveStandard),
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
          child: AnimatedOpacity(
            opacity: _lines.isEmpty ? 0.3 : 1.0,
            duration: Motion.durFast,
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
        ),
      ],
    );
  }
}
