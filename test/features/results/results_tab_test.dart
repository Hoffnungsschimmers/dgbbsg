import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLatency()', () {
    test('解析 "50.00 ms" 格式', () {
      expect(parseLatency('50.00 ms'), 50.0);
    });

    test('解析 "50.00ms" 格式（无空格）', () {
      expect(parseLatency('50.00ms'), 50.0);
    });

    test('解析纯数字', () {
      expect(parseLatency('123.45'), 123.45);
    });

    test('null 返回 null', () {
      expect(parseLatency(null), isNull);
    });

    test('空字符串返回 null', () {
      expect(parseLatency(''), isNull);
    });

    test('非数字返回 null', () {
      expect(parseLatency('abc'), isNull);
    });
  });

  group('ResultRow', () {
    test('ipPort 提取正确', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.ipPort, '1.2.3.4:443');
    });

    test('country 提取正确', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.country, isNotEmpty);
    });

    test('source 提取（空格分隔）', () {
      final row = ResultRow('1.2.3.4:443#US mia', '50.00 ms');
      expect(row.source, 'mia');
    });

    test('source 提取（@ 分隔，旧格式）', () {
      final row = ResultRow('1.2.3.4:443#US@cm', '50.00 ms');
      expect(row.source, 'cm');
    });

    test('无来源时 source 为空', () {
      final row = ResultRow('1.2.3.4:443#US', '50.00 ms');
      expect(row.source, isEmpty);
    });
  });

  group('parseResultLines()', () {
    test('解析新格式（空格分隔）', () {
      const text = '1.2.3.4:443#US mia 50.00 ms\n'
          '5.6.7.8:443#JP nrt 120.50ms\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(2));
      expect(rows[0].ipPort, '1.2.3.4:443');
      expect(rows[0].latency, '50.00 ms');
      expect(rows[1].ipPort, '5.6.7.8:443');
      expect(rows[1].latency, '120.50ms');
    });

    test('解析旧格式（@ 分隔）', () {
      const text = '1.2.3.4:443#US@cm 50.00 ms\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
      expect(rows[0].latency, '50.00 ms');
    });

    test('纯节点（无延迟）', () {
      const text = '1.2.3.4:443#US\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
      expect(rows[0].latency, isNull);
    });

    test('跳过空行和注释', () {
      const text = '# 注释\n\n1.2.3.4:443#US\n\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
    });

    test('跳过不含冒号的行', () {
      const text = 'invalid line\n1.2.3.4:443#US\n';
      final rows = parseResultLines(text);
      expect(rows, hasLength(1));
    });
  });

  group('ResultNotifier', () {
    late ResultNotifier notifier;

    setUp(() {
      notifier = ResultNotifier();
    });

    test('初始状态为空', () {
      expect(notifier.state.rows, isEmpty);
      expect(notifier.state.currentFile, isNull);
    });

    test('setRows 更新状态', () {
      notifier.setRows([ResultRow('1.2.3.4:443#US')], 'test.txt');
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.sourceLabel, 'test.txt');
    });

    test('addRow 添加节点', () {
      notifier.addRow('1.2.3.4:443#US');
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.rows[0].ipPort, '1.2.3.4:443');
    });

    test('addRow 忽略空行', () {
      notifier.addRow('');
      notifier.addRow('   ');
      expect(notifier.state.rows, isEmpty);
    });

    test('addRow 忽略无冒号行', () {
      notifier.addRow('invalid');
      expect(notifier.state.rows, isEmpty);
    });

    test('removeRow 删除指定索引', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.addRow('2.2.2.2:443#JP');
      notifier.removeRow(0);
      expect(notifier.state.rows, hasLength(1));
      expect(notifier.state.rows[0].ipPort, '2.2.2.2:443');
    });

    test('removeRow 越界不崩溃', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.removeRow(99);
      notifier.removeRow(-1);
      expect(notifier.state.rows, hasLength(1));
    });

    test('updateRow 更新节点', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.updateRow(0, '2.2.2.2:443#JP');
      expect(notifier.state.rows[0].ipPort, '2.2.2.2:443');
    });

    test('updateRow 保留延迟', () {
      notifier.setRows([ResultRow('1.1.1.1:443#US', '50 ms')]);
      notifier.updateRow(0, '2.2.2.2:443#JP');
      expect(notifier.state.rows[0].latency, '50 ms');
    });

    test('updateRow 越界不崩溃', () {
      notifier.addRow('1.1.1.1:443#US');
      notifier.updateRow(99, '2.2.2.2:443#JP');
      expect(notifier.state.rows, hasLength(1));
    });
  });
}
