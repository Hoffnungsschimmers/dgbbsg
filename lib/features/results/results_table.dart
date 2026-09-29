import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/motion.dart';
import '../../app/platform.dart';
import '../../app/theme.dart';
import '../widgets/common.dart';
import 'result_state.dart';

// ═══════════════════════════════════════════════════════
// 结果表格
// ═══════════════════════════════════════════════════════

class ResultTable extends StatefulWidget {
  const ResultTable({
    super.key,
    required this.rows,
    this.editMode = false,
    this.onDelete,
    this.onEdit,
    this.onReorder,
    this.sortCol = 0,
    this.sortAsc = true,
    this.onSort,
  });

  final List<ResultRow> rows;
  final bool editMode;
  final void Function(int index)? onDelete;
  final void Function(int index)? onEdit;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final int sortCol;
  final bool sortAsc;
  final void Function(int col)? onSort;

  static Widget _nodeCell(BuildContext context, String ipPort) {
    final t = AppThemeExt.of(context);
    final lastColon = ipPort.lastIndexOf(':');
    final rawHost = lastColon > 0 ? ipPort.substring(0, lastColon) : ipPort;
    final port = lastColon > 0 ? ipPort.substring(lastColon) : '';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: RichText(
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        text: TextSpan(
          style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14),
          children: [
            TextSpan(text: rawHost),
            if (port.isNotEmpty)
              TextSpan(text: port, style: TextStyle(color: t.textDim)),
          ],
        ),
      ),
    );
  }

  @override
  State<ResultTable> createState() => _ResultTableState();
}

class _ResultTableState extends State<ResultTable> {
  final _scrollCtl = ScrollController();

  @override
  void dispose() {
    _scrollCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final editMode = widget.editMode;
    final onReorder = widget.onReorder;
    final colWidths = editMode
        ? [FlexColumnWidth(3), FlexColumnWidth(4), IntrinsicColumnWidth()]
        : [FlexColumnWidth(3), FlexColumnWidth(4)];

    return card(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _headerRow(context, colWidths),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: Scrollbar(
              thumbVisibility: true,
              controller: _scrollCtl,
              child: editMode && onReorder != null
                  ? ReorderableListView.builder(
                      itemCount: rows.length,
                      onReorder: onReorder,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return _dataRow(context, i, row, colWidths, showDragHandle: true);
                      },
                    )
                  : ListView.builder(
                      controller: _scrollCtl,
                      itemCount: rows.length,
                      itemExtent: kIsMobile ? 64 : 60,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return _dataRow(context, i, row, colWidths);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow(BuildContext context, List<TableColumnWidth> colWidths) {
    final t = AppThemeExt.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceHover,
        border: Border(bottom: BorderSide(color: t.border, width: 1)),
      ),
      child: Table(
        columnWidths: {for (var i = 0; i < colWidths.length; i++) i: colWidths[i]},
        children: [
          TableRow(
            children: [
              _sortHeader(context, '节点', 0),
              _sortHeader(context, '注释', 1),
              if (widget.editMode) _th(context, ''),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, int index, ResultRow row, List<TableColumnWidth> colWidths, {bool showDragHandle = false}) {
    return _DataRowWidget(
      key: ValueKey('${row.ipPort}_$index'),
      index: index,
      row: row,
      colWidths: colWidths,
      editMode: widget.editMode,
      showDragHandle: showDragHandle,
      onEdit: widget.onEdit != null ? () => widget.onEdit!.call(index) : null,
      onDelete: widget.onDelete != null ? () => widget.onDelete!.call(index) : null,
    )
        .animate(delay: Motion.staggerDelay(index))
        .fadeIn(duration: Motion.staggerDur, curve: Motion.curveStandard)
        .slideX(begin: 0.03, end: 0, duration: Motion.staggerDur, curve: Motion.curveStandard);
  }

  Widget _sortHeader(BuildContext context, String label, int col) {
    final t = AppThemeExt.of(context);
    final isActive = widget.sortCol == col;
    return InkWell(
      onTap: () => widget.onSort?.call(col),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isActive ? t.text : t.textDim)),
            if (isActive) ...[
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: widget.sortAsc ? 0 : 0.5,
                duration: Motion.durFast,
                child: Icon(Icons.arrow_drop_up, size: 18, color: AppTheme.edgeOrange),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _th(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: t.textDim)));
  }
}

// ═══════════════════════════════════════════════════════
// 数据行
// ═══════════════════════════════════════════════════════

class _DataRowWidget extends StatefulWidget {
  final int index;
  final ResultRow row;
  final List<TableColumnWidth> colWidths;
  final bool editMode;
  final bool showDragHandle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _DataRowWidget({
    super.key,
    required this.index,
    required this.row,
    required this.colWidths,
    required this.editMode,
    this.showDragHandle = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<_DataRowWidget> createState() => _DataRowWidgetState();
}

class _DataRowWidgetState extends State<_DataRowWidget> {
  bool _hovered = false;

  /// 注释单元格。
  Widget _annotationCell(BuildContext context, String annotation) {
    final t = AppThemeExt.of(context);
    final text = Text(
      annotation.isEmpty ? '—' : annotation,
      style: TextStyle(color: annotation.isEmpty ? t.textDim : t.text, fontSize: 13),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 备注 = 来源名 + 原始节点名，常超出列宽，悬停给出全文。
          annotation.isEmpty ? text : Tooltip(message: annotation, child: text),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final baseColor =
        (widget.index.isOdd ? t.surfaceHover.withValues(alpha: 0.3) : Colors.transparent);
    final hoverColor = _hovered
        ? t.accentSoft.withValues(alpha: 0.45)
        : baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.editMode) {
            widget.onEdit?.call();
          } else {
            Clipboard.setData(ClipboardData(text: widget.row.ipPort));
            if (context.mounted) {
              AppToast.show(context, '已复制 ${widget.row.ipPort}');
            }
          }
        },
        child: AnimatedContainer(
          duration: Motion.durFast,
          curve: Motion.curveStandard,
          decoration: BoxDecoration(
            color: hoverColor,
          ),
          child: Table(
            columnWidths: {for (var i = 0; i < widget.colWidths.length; i++) i: widget.colWidths[i]},
            children: [
              TableRow(children: [
                ResultTable._nodeCell(context, widget.row.ipPort),
                _annotationCell(context, widget.row.annotation),
                if (widget.editMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.showDragHandle)
                          ReorderableDragStartListener(
                            index: widget.index,
                            child: Icon(Icons.drag_handle, size: 18, color: t.textDim),
                          ),
                        if (widget.showDragHandle) const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.edit_outlined, size: 18, color: AppTheme.edgeOrange),
                          tooltip: '编辑',
                          onPressed: widget.onEdit,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(
                            minWidth: kIsMobile ? 48 : 32,
                            minHeight: kIsMobile ? 48 : 32,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: t.danger),
                          tooltip: '删除',
                          onPressed: widget.onDelete,
                          iconSize: 18,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(
                            minWidth: kIsMobile ? 48 : 32,
                            minHeight: kIsMobile ? 48 : 32,
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
