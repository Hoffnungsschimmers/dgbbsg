import 'package:flutter/material.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';

/// 可折叠分区（带 chevron 旋转 + 内容淡入/尺寸动效）。
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
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _ctrl = AnimationController(
      vsync: this,
      duration: Motion.durBase,
      value: _expanded ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
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
                    turns: Tween(begin: 0.0, end: 0.5).animate(_ctrl),
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
                ? FadeTransition(
                    opacity: _ctrl,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: t.border),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: widget.child,
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
