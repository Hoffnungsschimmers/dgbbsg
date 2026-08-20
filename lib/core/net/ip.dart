import 'dart:io';

/// 判断 host 是否为 IP 地址（IPv4 或 IPv6，支持方括号包裹的 IPv6）。
bool isIp(String host) => isIpv4(host) || isIpv6(host);

bool isIpv4(String host) {
  if (host.isEmpty) return false;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  return parts.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255;
  });
}

bool isIpv6(String host) {
  final h = host.replaceAll(RegExp(r'[\[\]]'), '');
  if (h.isEmpty) return false;
  return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(h) && h.contains(':');
}

/// 确保节点字符串（`ip:port#注释`）中的 IPv6 主机部分带上方括号（幂等）。
/// 例：`2606:4700:8394:...:b7da:443#US` → `[2606:4700:8394:...:b7da]:443#US`
///     `2001:db8::1` → `[2001:db8::1]`
///     `1.2.3.4:443#US` / `example.com:443#US` / `[2606:...]:443` → 不变
String bracketIpv6Host(String endpoint) {
  final hashIdx = endpoint.indexOf('#');
  final base = (hashIdx < 0 ? endpoint : endpoint.substring(0, hashIdx)).trim();
  if (base.isEmpty || base.startsWith('[')) return endpoint;
  final annotation = hashIdx < 0 ? '' : endpoint.substring(hashIdx);

  final idx = base.lastIndexOf(':');
  if (idx < 0) {
    // 无端口：整个 base 就是 IP
    return isIpv6(base) ? '[$base]$annotation' : endpoint;
  }
  final ip = base.substring(0, idx);
  final port = base.substring(idx + 1);

  if (ip.endsWith(':')) {
    // 形如 2001:db8::1 —— 最后一段属于地址本体（无端口）
    return isIpv6(base) ? '[$base]$annotation' : endpoint;
  }
  // 裸 IPv6:port（至少 3 段，或含 ::）
  if (ip.contains(':') && (ip.contains('::') || ip.split(':').length >= 3)) {
    if (port.isEmpty) return '[$ip]$annotation';
    if (int.tryParse(port) != null) return '[$ip]:$port$annotation';
  }
  return endpoint;
}

/// 判断 IPv4 地址是否属于 Cloudflare Anycast 段。
/// 已知 CF 段：104.16.0.0/12, 162.158.0.0/15, 172.64.0.0/13,
///   108.162.192.0/18, 13.32.0.0/13, 13.35.0.0/16, 13.224.0.0/13, 13.249.0.0/16
bool isCloudflareIp(String ip) {
  if (!isIpv4(ip)) return false;
  final parts = ip.split('.').map(int.parse).toList();
  final a = parts[0], b = parts[1];
  if (a == 104 && b >= 16 && b <= 31) return true;   // 104.16.0.0/12
  if (a == 162 && (b == 158 || b == 159)) return true; // 162.158.0.0/15
  if (a == 172 && b >= 64 && b <= 71) return true;     // 172.64.0.0/13
  if (a == 108 && b == 162) return true;                // 108.162.192.0/18
  if (a == 13 && b >= 32 && b <= 35) return true;       // 13.32.0.0/13
  if (a == 13 && b >= 224 && b <= 231) return true;       // 13.224.0.0/13
  if (a == 13 && b == 249) return true;                  // 13.249.0.0/16
  return false;
}

/// ISO 3166-1 alpha-2 国家码 → 中文名称 映射。
String countryCodeToName(String code) {
  return _countryNameMap[code.toUpperCase()] ?? code;
}

const _countryNameMap = <String, String>{
  'CN': '中国', 'HK': '香港', 'TW': '台湾', 'MO': '澳门', 'JP': '日本',
  'KR': '韩国', 'SG': '新加坡', 'MY': '马来西亚', 'TH': '泰国', 'VN': '越南',
  'PH': '菲律宾', 'ID': '印尼', 'IN': '印度', 'PK': '巴基斯坦', 'BD': '孟加拉',
  'LK': '斯里兰卡', 'NP': '尼泊尔', 'MM': '缅甸', 'KH': '柬埔寨', 'LA': '老挝',
  'BN': '文莱', 'MN': '蒙古',
  'US': '美国', 'CA': '加拿大', 'MX': '墨西哥',
  'GB': '英国', 'DE': '德国', 'FR': '法国', 'NL': '荷兰', 'IT': '意大利',
  'ES': '西班牙', 'PT': '葡萄牙', 'CH': '瑞士', 'AT': '奥地利', 'BE': '比利时',
  'DK': '丹麦', 'SE': '瑞典', 'NO': '挪威', 'FI': '芬兰', 'PL': '波兰',
  'CZ': '捷克', 'HU': '匈牙利', 'RO': '罗马尼亚', 'BG': '保加利亚', 'GR': '希腊',
  'RS': '塞尔维亚', 'HR': '克罗地亚', 'SK': '斯洛伐克', 'EE': '爱沙尼亚',
  'LV': '拉脱维亚', 'LT': '立陶宛', 'UA': '乌克兰', 'RU': '俄罗斯',
  'AM': '亚美尼亚', 'GE': '格鲁吉亚', 'AZ': '阿塞拜疆',
  'KZ': '哈萨克斯坦', 'UZ': '乌兹别克斯坦', 'KG': '吉尔吉斯斯坦', 'TJ': '塔吉克斯坦', 'TM': '土库曼斯坦',
  'TR': '土耳其', 'IL': '以色列', 'SA': '沙特', 'AE': '阿联酋', 'QA': '卡塔尔',
  'BH': '巴林', 'KW': '科威特', 'OM': '阿曼', 'JO': '约旦', 'IQ': '伊拉克',
  'IR': '伊朗',
  'BR': '巴西', 'AR': '阿根廷', 'CL': '智利', 'CO': '哥伦比亚', 'PE': '秘鲁',
  'VE': '委内瑞拉', 'EC': '厄瓜多尔', 'UY': '乌拉圭', 'PY': '巴拉圭',
  'BO': '玻利维亚', 'PA': '巴拿马', 'CR': '哥斯达黎加',
  'AU': '澳大利亚', 'NZ': '新西兰',
  'ZA': '南非', 'EG': '埃及', 'MA': '摩洛哥', 'NG': '尼日利亚', 'KE': '肯尼亚',
  'ET': '埃塞俄比亚', 'TZ': '坦桑尼亚', 'GH': '加纳', 'SN': '塞内加尔',
  'TN': '突尼斯', 'DZ': '阿尔及利亚', 'RW': '卢旺达', 'UG': '乌干达',
  'MZ': '莫桑比克', 'MG': '马达加斯加', 'CM': '喀麦隆', 'CF': '中非',
  'NC': '新喀里多尼亚',
};

/// Cloudflare 边缘节点机场码 → ISO 3166-1 alpha-2 国家码映射。
/// 覆盖全球主要 Cloudflare 节点。未匹配时返回空串。
String cfAirportToCountry(String airport) {
  return _cfAirportMap[airport.toUpperCase()] ?? '';
}

const _cfAirportMap = <String, String>{
  // 东亚
  'NRT': 'JP', 'KIX': 'JP', 'TYO': 'JP', 'FUK': 'JP', 'NGO': 'JP', 'CTS': 'JP',
  'ICN': 'KR', 'GMP': 'KR', 'PUS': 'KR',
  'TPE': 'TW', 'KHH': 'TW',
  'HKG': 'HK',
  'MFM': 'MO',
  // 东南亚
  'SIN': 'SG', 'BKK': 'TH', 'KUL': 'MY', 'CGK': 'ID', 'MNL': 'PH',
  'SGN': 'VN', 'HAN': 'VN', 'RGN': 'MM', 'PNH': 'KH', 'VTE': 'LA',
  // 南亚
  'DEL': 'IN', 'BOM': 'IN', 'MAA': 'IN', 'BLR': 'IN', 'CCU': 'IN', 'HYD': 'IN',
  'CMB': 'LK', 'DAC': 'BD', 'KTM': 'NP', 'KHI': 'PK', 'ISB': 'PK', 'LHE': 'PK',
  // 中东
  'DXB': 'AE', 'AUH': 'AE', 'DOH': 'QA', 'BAH': 'BH', 'KWI': 'KW',
  'RUH': 'SA', 'JED': 'SA', 'MCT': 'OM', 'AMM': 'JO', 'BGW': 'IQ',
  'TLV': 'IL', 'IST': 'TR', 'SAW': 'TR', 'ESB': 'TR',
  'THR': 'IR',
  // 欧洲
  'LHR': 'GB', 'LGW': 'GB', 'MAN': 'GB', 'EDI': 'GB',
  'CDG': 'FR', 'ORY': 'FR', 'MRS': 'FR',
  'FRA': 'DE', 'MUC': 'DE', 'DUS': 'DE', 'TXL': 'DE', 'HAM': 'DE',
  'AMS': 'NL',
  'FCO': 'IT', 'MXP': 'IT', 'LIN': 'IT',
  'MAD': 'ES', 'BCN': 'ES',
  'LIS': 'PT', 'OPO': 'PT',
  'ZRH': 'CH', 'GVA': 'CH',
  'VIE': 'AT',
  'BRU': 'BE',
  'CPH': 'DK',
  'ARN': 'SE', 'GOT': 'SE',
  'OSL': 'NO', 'BGO': 'NO',
  'HEL': 'FI',
  'WAW': 'PL', 'KRK': 'PL',
  'PRG': 'CZ',
  'BUD': 'HU',
  'OTP': 'RO',
  'SOF': 'BG',
  'ATH': 'GR',
  'SKG': 'GR',
  'BEG': 'RS',
  'ZAG': 'HR',
  'BTS': 'SK',
  'TLL': 'EE', 'RIX': 'LV', 'VNO': 'LT',
  'KBP': 'UA', 'ODS': 'UA',
  'DME': 'RU', 'SVO': 'RU', 'LED': 'RU', 'SVX': 'RU', 'OVB': 'RU',
  // 北美
  'IAD': 'US', 'EWR': 'US', 'JFK': 'US', 'LGA': 'US', 'MIA': 'US',
  'ATL': 'US', 'ORD': 'US', 'DFW': 'US', 'LAX': 'US', 'SFO': 'US',
  'SEA': 'US', 'DEN': 'US', 'PHX': 'US', 'IAH': 'US', 'MSP': 'US',
  'DTW': 'US', 'BOS': 'US', 'PHL': 'US', 'CLT': 'US', 'MCO': 'US',
  'SAN': 'US', 'TPA': 'US', 'PDX': 'US', 'SLC': 'US', 'STL': 'US',
  'BNA': 'US', 'AUS': 'US', 'RDU': 'US', 'MCI': 'US', 'SMF': 'US',
  'SJC': 'US', 'OAK': 'US', 'HNL': 'US', 'DCA': 'US', 'BWI': 'US',
  'YYZ': 'CA', 'YVR': 'CA', 'YUL': 'CA', 'YYC': 'CA', 'YOW': 'CA',
  'YEG': 'CA', 'YHZ': 'CA',
  'MEX': 'MX', 'GDL': 'MX', 'CUN': 'MX', 'MTY': 'MX',
  // 南美
  'GRU': 'BR', 'GIG': 'BR', 'BSB': 'BR', 'SSA': 'BR', 'FOR': 'BR', 'MAO': 'BR', 'CGH': 'BR',
  'EZE': 'AR', 'SCL': 'CL', 'BOG': 'CO', 'LIM': 'PE',
  'CCS': 'VE', 'UIO': 'EC', 'PTY': 'PA', 'SJO': 'CR',
  'GYE': 'EC', 'MVD': 'UY', 'ASU': 'PY', 'LPB': 'BO',
  // 非洲
  'JNB': 'ZA', 'CPT': 'ZA', 'DUR': 'ZA',
  'CAI': 'EG', 'ALY': 'EG',
  'CMN': 'MA', 'RBA': 'MA',
  'LOS': 'NG', 'ABV': 'NG',
  'NBO': 'KE', 'MBA': 'KE',
  'ADD': 'ET',
  'DAR': 'TZ',
  'ACC': 'GH',
  'DKK': 'SN',
  'TUN': 'TN',
  'ALG': 'DZ',
  'KGL': 'RW',
  'EBB': 'UG',
  'MPM': 'MZ',
  'TNR': 'MG',
  // 大洋洲
  'SYD': 'AU', 'MEL': 'AU', 'BNE': 'AU', 'PER': 'AU', 'ADL': 'AU', 'CBR': 'AU',
  'AKL': 'NZ', 'WLG': 'NZ', 'CHC': 'NZ',
  'NOU': 'NC',
};

/// 批量通过 cdn-cgi/trace 识别多个 IP 的地区，复用单个 [HttpClient]。
///
/// 比逐个调用 [geolocateCfIp] 更高效：避免为每个 IP 创建/销毁 HttpClient。
/// 返回 IP → 国家码 映射，失败的 IP 不在结果中。
Future<Map<String, String>> geolocateCfIpBatch(
  List<String> ips, {
  Duration? timeout,
  String? proxy,
}) async {
  if (ips.isEmpty) return {};
  final t = timeout ?? const Duration(milliseconds: 2500);
  final result = <String, String>{};

  Future<String> traceOne(HttpClient client, String ip) async {
    // IPv6 在 URL 中必须带方括号
    final host = isIpv6(ip) ? '[$ip]' : ip;
    for (final scheme in ['http', 'https']) {
      try {
        final req = await client.getUrl(Uri.parse('$scheme://$host/cdn-cgi/trace'));
        req.headers.set('Host', 'www.cloudflare.com');
        final resp = await req.close().timeout(t);
        final body = await resp.transform(SystemEncoding().decoder).join();
        final match = RegExp(r'colo=(\w+)').firstMatch(body);
        if (match != null) {
          final airport = match.group(1)!;
          final cc = cfAirportToCountry(airport);
          if (cc.isNotEmpty) return cc;
        }
      } catch (_) {}
    }
    return '';
  }

  final client = HttpClient()..connectionTimeout = t;
  if (proxy != null && proxy.isNotEmpty) {
    client.findProxy = (uri) => 'PROXY $proxy';
  }
  try {
    await Future.wait(ips.map((ip) async {
      final cc = await traceOne(client, ip);
      if (cc.isNotEmpty) result[ip] = cc;
    }));
  } finally {
    client.close(force: true);
  }
  return result;
}
