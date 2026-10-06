import 'package:cfnb_app/features/subscriptions/config_entries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('订阅器条目 名称|域名|secret', () {
    test('三段各自归位', () {
      const entry = '我的订阅器|sub.example.com|secret123';
      expect(generatorName(entry), '我的订阅器');
      expect(generatorHost(entry), 'sub.example.com');
      expect(generatorSecret(entry), 'secret123');
    });

    test('只有域名时整个条目即域名，密钥为空', () {
      expect(generatorHost('sub.example.com'), 'sub.example.com');
      expect(generatorName('sub.example.com'), 'sub.example.com');
      expect(generatorSecret('sub.example.com'), '');
    });

    test('密钥自身含 | 时不截断', () {
      expect(generatorSecret('n|host|a|b|c'), 'a|b|c');
    });

    test('段两侧空白被去掉', () {
      expect(generatorName('  名称 | host '), '名称');
      expect(generatorHost(' 名称 |  host | s '), 'host');
    });
  });

  group('订阅链接条目的备注剥离', () {
    test('http(s) 订阅地址支持「备注|URL」', () {
      const entry = '备注A|https://sub.example.com/sub?token=x';
      expect(urlNote(entry), '备注A');
      expect(urlValue(entry), 'https://sub.example.com/sub?token=x');
    });

    test('无备注前缀时整条即链接', () {
      const url = 'https://sub.example.com/sub';
      expect(urlNote(url), '');
      expect(urlValue(url), url);
    });

    // 硬教训：判断有无标签前缀只能用 supportedSchemes 前缀比对。
    // 用 contains('://') 会把下面这条误判成节点链接，导致备注丢失、源名错误。
    test('备注本身含 :// 的订阅地址仍按带标签处理', () {
      const entry = '备注 https://x 自用|https://sub.example.com/sub';
      expect(urlNote(entry), '备注 https://x 自用');
      expect(urlValue(entry), 'https://sub.example.com/sub');
    });

    test('节点分享链接本身不带备注，且不被 | 切断', () {
      const node =
          'vless://uuid-uuid-uuid@1.2.3.4:443?security=tls#日本 01';
      expect(urlNote(node), '');
      expect(urlValue(node), node);
    });

    test('| 之后为空时保留整条', () {
      expect(urlValue('备注|'), '备注|');
      expect(urlValue('备注|   '), '备注|');
    });
  });

  group('备注与链接拼回存储格式', () {
    test('有备注才加 |', () {
      expect(joinNoteValue('备注A', 'https://sub.example.com/sub'),
          '备注A|https://sub.example.com/sub');
      expect(joinNoteValue('  ', 'https://sub.example.com/sub'),
          'https://sub.example.com/sub');
    });

    test('节点分享链接不拼备注', () {
      const node = 'trojan://pass@1.2.3.4:443#HK';
      expect(joinNoteValue('旧备注', node), node);
    });

    test('拆出去再拼回来不变形', () {
      for (final entry in [
        '备注A|https://sub.example.com/sub?token=x',
        'https://sub.example.com/sub',
        'vless://uuid@1.2.3.4:443#日本 01',
      ]) {
        expect(joinNoteValue(urlNote(entry), urlValue(entry)), entry);
      }
    });
  });
}
