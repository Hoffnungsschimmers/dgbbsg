import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../settings/settings_fields.dart';
import '../widgets/common.dart';

/// 字段变更回调：父级负责写回草稿并持久化。
typedef KeySaver = void Function(String key, dynamic value);

/// 数据驱动字段渲染：按 [SettingField.type] 渲染对应表单控件。
/// 所有文本输入均走「差异守护」同步（`if (ctl.text != v) ctl.text = v`），
/// 修复"输入一个字符后自动全选覆盖"的 bug。
class FieldList extends StatefulWidget {
  final List<SettingField> fields;
  final Map<String, dynamic> draft;
  final KeySaver onSave;
  const FieldList({super.key, required this.fields, required this.draft, required this.onSave});

  @override
  State<FieldList> createState() => _FieldListState();
}

class _FieldListState extends State<FieldList> {
  final Map<String, TextEditingController> _ctl = {};

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  dynamic _v(String key) => widget.draft[key];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in widget.fields) ...[
          _render(f),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _render(SettingField f) {
    final key = f.key;
    switch (f.type) {
      case 'bool':
        return switchRow(context, f.label, (_v(key) as bool?) ?? false,
            (v) => widget.onSave(key, v));
      case 'string':
        final c = _ctl.putIfAbsent(key, () => TextEditingController());
        final v = (_v(key) as String?) ?? '';
        if (c.text != v) c.text = v;
        return textRow(context, f.label, c, (v) => widget.onSave(key, v),
            obscure: key == 'GITHUB_TOKEN', mono: _monoKey(key));
      case 'int':
        final opt = _opts(f, [0, 100, 1]);
        return sliderRowInt(context, f.label, (_v(key) as num?)?.toInt() ?? opt[0],
            opt[0], opt[1], (v) => widget.onSave(key, v));
      case 'float':
        final opt = _opts(f, [0.0, 1.0, 0.1]);
        return sliderRowDouble(
            context, f.label, ((_v(key) as num?) ?? opt[0]).toDouble(),
            opt[0].toDouble(), opt[1].toDouble(), (v) => widget.onSave(key, v));
      case 'choice':
        return _choice(f);
      case 'list_str':
        return _listEditor(f);
      default:
        return textRow(context, f.label, TextEditingController(), (_) {},
            mono: false);
    }
  }

  List<dynamic> _opts(SettingField f, List<dynamic> fallback) =>
      (f.opts != null && f.opts!.length >= 3) ? f.opts! : fallback;

  bool _monoKey(String key) =>
      key.contains('HOST') ||
      key.contains('UUID') ||
      key.contains('FILE') ||
      key.contains('SNI') ||
      key.contains('URL') ||
      key.contains('REPO') ||
      key.contains('BRANCH') ||
      key.contains('TOKEN') ||
      key.contains('IP');

  Widget _choice(SettingField f) {
    final t = AppThemeExt.of(context);
    final options = (f.opts ?? const []).map((e) => e.toString()).toList();
    final value =
        (_v(f.key) as String?) ?? (options.isNotEmpty ? options.first : '');
    if (options.length <= 3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label, style: TextStyle(fontSize: 12, color: t.textDim)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              for (final o in options)
                ButtonSegment(value: o, label: Text(_choiceLabel(f.key, o))),
            ],
            selected: {value},
            onSelectionChanged: (s) => widget.onSave(f.key, s.first),
          ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: f.label),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(_choiceLabel(f.key, o))),
      ],
      onChanged: (v) {
        if (v != null) widget.onSave(f.key, v);
      },
    );
  }

  String _choiceLabel(String key, String v) {
    if (key == 'SUB_INPUT_MODE') {
      return switch (v) {
        'node' => '订阅器',
        'url' => '订阅链接',
        'both' => '两者',
        _ => v,
      };
    }
    if (key == 'GUI_THEME') return v == 'light' ? '浅色' : '深色';
    return v;
  }

  Widget _listEditor(SettingField f) {
    final t = AppThemeExt.of(context);
    final values =
        ((_v(f.key) as List?) ?? const []).map((e) => e.toString()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label, style: TextStyle(fontSize: 12, color: t.textDim)),
        const SizedBox(height: 6),
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: _listField('${f.key}:$i', values[i],
                      (v) => widget.onSave(f.key, _setAt(values, i, v))),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: '删除',
                  onPressed: () => widget.onSave(f.key, _removeAt(values, i)),
                ),
              ],
            ),
          ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('添加'),
          onPressed: () => widget.onSave(f.key, [...values, '']),
        ),
        if (f.key == 'SUB_GENERATORS')
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('格式：名称|域名（可带端口）',
                style: TextStyle(fontSize: 11, color: t.textDim)),
          ),
      ],
    );
  }

  Widget _listField(String ctlKey, String value, ValueChanged<String> onChanged) {
    final c = _ctl.putIfAbsent(ctlKey, () => TextEditingController());
    if (c.text != value) c.text = value;
    return TextField(
      controller: c,
      onChanged: onChanged,
      style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
    );
  }

  List<String> _setAt(List<String> list, int i, String v) {
    final out = [...list];
    out[i] = v;
    return out;
  }

  List<String> _removeAt(List<String> list, int i) {
    return [...list]..removeAt(i);
  }
}