import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveOutputPath 拼接文档目录', () {
    final resolved = resolveOutputPath('addressesapi.txt', '/data/user/0/app/doc');
    expect(resolved, endsWith('addressesapi.txt'));
  });

  test('绝对路径原样返回', () {
    final resolved = resolveOutputPath('/tmp/x.txt', '/doc');
    expect(resolved, '/tmp/x.txt');
  });
}
