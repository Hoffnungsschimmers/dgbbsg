import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析纯节点与延迟，无带宽/质量分', () {
    final rows = parseResultLines('1.2.3.4:443#US 50.00 ms\n9.9.9.9:443#HK');
    expect(rows.length, 2);
    expect(rows[0].node, '1.2.3.4:443#US');
    expect(rows[0].latency, '50.00 ms');
    expect(rows[0].country, '美国');
    expect(rows[1].latency, isNull);
  });

  test('ResultRow 仅含 node/latency', () {
    final r = ResultRow('1.2.3.4:443#US', '50.00 ms');
    expect(r.node, '1.2.3.4:443#US');
    expect(r.latency, '50.00 ms');
    expect(r.country, '美国');
  });

  test('parseResultLines 裸 IPv6 自动加方括号', () {
    final rows =
        parseResultLines('2606:4700:8394:b884:22e2:7cb7:25bd:b7da:443#US 50.00 ms');
    expect(
      rows.single.node,
      '[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#US',
    );
  });

  test('addRow 裸 IPv6 自动加方括号', () {
    final n = ResultNotifier();
    n.addRow('2606:4700:8394:b884:22e2:7cb7:25bd:b7da:443#US');
    expect(
      n.state.rows.single.node,
      '[2606:4700:8394:b884:22e2:7cb7:25bd:b7da]:443#US',
    );
  });
}
