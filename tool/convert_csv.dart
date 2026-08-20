import 'dart:convert';
import 'dart:io';

const cityToCc = {
  // 亚洲
  '香港': 'HK',
  '新加坡': 'SG',
  '东京': 'JP',
  '大阪': 'JP',
  '福冈': 'JP',
  '首尔': 'KR',
  '台北': 'TW',
  '高雄市': 'TW',
  '曼谷': 'TH',
  '吉隆坡': 'MY',
  '雅加达': 'ID',
  '日惹': 'ID',
  '马尼拉': 'PH',
  '孟买': 'IN',
  '新德里': 'IN',
  '海得拉巴': 'IN',
  '班加罗尔': 'IN',
  '金奈': 'IN',
  '迪拜': 'AE',
  '马斯喀特': 'OM',
  '利雅得': 'SA',
  '吉达': 'SA',
  '巴库': 'AZ',
  '第比利斯': 'GE',
  '埃里温': 'AM',
  '阿拉木图': 'KZ',
  '阿克托别': 'KZ',
  '比什凯克': 'KG',
  '特拉维夫': 'IL',
  '安曼': 'JO',
  '卡拉奇': 'PK',
  '达卡': 'BD',
  '吉大港': 'BD',
  '加德满都': 'NP',
  '乌兰巴托': 'MN',
  '阿尔纳武特柯伊': 'TR',  // 伊斯坦布尔附近
  '利马': 'PE',
  '基多': 'EC',
  '波哥大': 'CO',
  '圣地亚哥': 'CL',
  '布宜诺斯艾利斯': 'AR',
  '埃塞萨': 'AR',
  '圣保罗': 'BR',
  '福塔雷萨': 'BR',
  '里约热内卢': 'BR',
  '克雷塔罗': 'MX',
  '圣多明各': 'DO',

  // 北美
  '杜勒斯': 'US',
  '西雅图': 'US',
  '洛杉矶': 'US',
  '圣何塞': 'US',
  '纽瓦克': 'US',
  '芝加哥': 'US',
  '达拉斯-沃斯堡': 'US',
  '亚特兰大': 'US',
  '拉斯维加斯': 'US',
  '波特兰': 'US',
  '迈阿密': 'US',
  '水牛城': 'US',
  '堪萨斯城': 'US',
  '盐湖城': 'US',
  '哥伦布': 'US',
  '圣路易斯': 'US',
  '菲尼克斯': 'US',
  '檀香山': 'US',
  '休斯顿': 'US',
  '丹佛': 'US',
  '明尼阿波利斯': 'US',
  '杰克逊维尔': 'US',
  '坦帕': 'US',
  '波士顿': 'US',
  '多伦多': 'CA',
  '蒙特利尔': 'CA',
  '温哥华': 'CA',
  '温尼伯': 'CA',

  // 欧洲
  '法兰克福': 'DE',
  '杜塞尔多夫': 'DE',
  '柏林': 'DE',
  '汉堡': 'DE',
  '慕尼黑': 'DE',
  '伦敦': 'GB',
  '曼彻斯特': 'GB',
  '巴黎': 'FR',
  '马赛': 'FR',
  '里昂': 'FR',
  '阿姆斯特丹': 'NL',
  '都柏林': 'IE',
  '莫斯科': 'RU',
  '明斯克': 'BY',
  '斯德哥尔摩': 'SE',
  '哥德堡': 'SE',
  '赫尔辛基': 'FI',
  '华沙': 'PL',
  '弗罗茨瓦夫': 'PL',
  '塔林': 'EE',
  '里加': 'LV',
  '维尔纽斯': 'LT',
  '维也纳': 'AT',
  '布拉格': 'CZ',
  '布拉迪斯拉发': 'SK',
  '布达佩斯': 'HU',
  '布加勒斯特': 'RO',
  '索菲亚': 'BG',
  '贝尔格莱德': 'RS',
  '萨格勒布': 'HR',
  '地拉那': 'AL',
  '马德里': 'ES',
  '巴塞罗那': 'ES',
  '里斯本': 'PT',
  '米兰': 'IT',
  '巴勒莫': 'IT',
  '罗马': 'IT',
  '苏黎世': 'CH',
  '日内瓦': 'CH',
  '布鲁塞尔': 'BE',
  '哥本哈根': 'DK',
  '奥斯陆': 'NO',
  '雷克雅未克': 'IS',
  '雅典': 'GR',
  '拉纳卡': 'CY',
  '卢森堡': 'LU',

  // 非洲
  '约翰内斯堡': 'ZA',
  '开普敦': 'ZA',
  '拉各斯': 'NG',
  '阿尔及尔': 'DZ',

  // 大洋洲
  '悉尼': 'AU',
  '墨尔本': 'AU',
  '珀斯': 'AU',
  '奥克兰': 'NZ',

  // 其他
  '其他城市': '',
};

/// 简易 CSV 行解析（支持带引号的字段，如 "Amazon.com, Inc."）
List<String> _parseCsvLine(String line) {
  final cols = <String>[];
  var i = 0;
  while (i < line.length) {
    if (line[i] == '"') {
      // 带引号字段
      final end = line.indexOf('"', i + 1);
      if (end < 0) {
        cols.add(line.substring(i + 1));
        break;
      }
      cols.add(line.substring(i + 1, end));
      i = end + 1;
      if (i < line.length && line[i] == ',') i++;
    } else {
      final end = line.indexOf(',', i);
      if (end < 0) {
        cols.add(line.substring(i));
        break;
      }
      cols.add(line.substring(i, end));
      i = end + 1;
    }
  }
  return cols;
}

Future<void> main() async {
  final csvFile = File(r'C:\Users\2540\Downloads\Telegram Desktop\Global-proxyip-443.csv');
  final lines = csvFile.readAsLinesSync(encoding: utf8);

  final rows = <Map<String, String>>[];
  for (var i = 1; i < lines.length; i++) {
    final cols = _parseCsvLine(lines[i]);
    if (cols.length < 18) continue;
    rows.add({
      'ip': cols[1].trim(),
      'port': cols[2].trim(),
      'dc': cols[4].trim(),
      'city_cn': cols[10].trim(),
      'latency': cols[12].trim(),
      'asn_org': cols[17].trim(),
    });
  }

  // 去重 by ip:port#CC
  final seen = <String>{};
  final unique = <Map<String, String>>[];
  for (final r in rows) {
    final cc = cityToCc[r['city_cn']] ?? '';
    final key = '${r['ip']}:${r['port']}#$cc';
    if (seen.add(key)) {
      unique.add({...r, 'cc': cc});
    }
  }

  // 写输出
  final outFile = File(r'C:\Users\2540\Downloads\Telegram Desktop\proxyip_443_converted.txt');
  final sink = outFile.openWrite(encoding: utf8);

  sink.writeln('# Global-proxyip-443.csv 转换结果');
  sink.writeln('# 来源: TG@danfeng_chat | 总行数: ${rows.length} | 去重后: ${unique.length}');
  sink.writeln('# 格式: ip:port#CC');
  sink.writeln('#');
  sink.writeln('# 用法: 粘贴到 CF优选 app 的「订阅源」地址框，运行「订阅IP」即可');
  sink.writeln('#');

  // 按地区分组输出
  final groups = <String, List<Map<String, String>>>{};
  for (final r in unique) {
    groups.putIfAbsent(r['cc']!, () => []).add(r);
  }

  for (final entry in groups.entries) {
    sink.writeln('#');
    sink.writeln('# === ${entry.key} (${entry.value.length} 个) ===');
    for (final r in entry.value) {
      sink.writeln('${r['ip']}:${r['port']}#${r['cc']}  # ${r['dc']} ${r['city_cn']} ${r['latency']} ${r['asn_org']}');
    }
  }

  await sink.flush();
  sink.close();

  // 统计
  print('转换完成: ${rows.length} 行 → 去重后 ${unique.length} 个节点');
  print('输出文件: ${outFile.path}');
  print('');
  print('按地区分布:');
  for (final entry in groups.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length))) {
    print('  ${entry.key}: ${entry.value.length} 个');
  }
}
