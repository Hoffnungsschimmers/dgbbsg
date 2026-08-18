import 'dart:io';
import 'dart:math';

/// Cloudflare 已知 IPv4 CIDR 段列表（本地兜底，API 获取失败时使用）。
const List<String> cfIPv4Ranges = [
  '104.16.0.0/12',
  '162.158.0.0/15',
  '172.64.0.0/13',
  '108.162.192.0/18',
  '13.32.0.0/13',
  '13.224.0.0/13',
  '13.249.0.0/16',
  '104.24.0.0/14',
  '172.67.0.0/16',
  '141.101.0.0/16',
  '103.21.244.0/22',
  '103.22.200.0/22',
  '103.31.4.0/22',
  '188.114.96.0/20',
  '190.93.240.0/20',
  '197.234.240.0/22',
  '198.41.128.0/17',
];

const _cfIpsApiUrl = 'https://www.baipiao.eu.org/cloudflare/ips-v4';

class CfRangeScanner {
  /// 获取 CF IPv4 子网列表（API 优先，失败回退本地硬编码）。
  static Future<List<String>> fetchSubnets() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse(_cfIpsApiUrl));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        final body = await resp.transform(SystemEncoding().decoder).join();
        final lines = body.split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && l.contains('/'))
            .toList();
        if (lines.isNotEmpty) return lines;
      } finally {
        client.close(force: true);
      }
    } catch (_) {}
    // 回退到本地硬编码列表
    return cfIPv4Ranges;
  }

  /// 从子网列表中每个 /24 子网随机取 1 个 IP（与原项目 CFData-WEB 逻辑一致）。
  static Future<List<String>> generateIPs({void Function(String)? onLog}) async {
    final subnets = await fetchSubnets();
    onLog?.call('获取到 ${subnets.length} 个 CF 子网');
    final rng = Random();
    final ips = <String>[];
    for (final subnet in subnets) {
      final ip = _randomIpFromCIDR(subnet, rng);
      if (ip != null) ips.add(ip);
    }
    onLog?.call('生成 ${ips.length} 个待测 IP');
    return ips;
  }

  /// 从 CIDR 段中随机生成一个 IP。
  /// /24 及更小的段：每个段取 1 个随机 IP。
  /// 更大的段（如 /12）：展开为 /24 子网，每个子网取 1 个。
  static String? _randomIpFromCIDR(String cidr, Random rng) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final prefix = parts[0];
    final prefixLen = int.tryParse(parts[1]);
    if (prefixLen == null) return null;
    final octets = prefix.split('.').map(int.parse).toList();
    if (octets.length != 4) return null;
    final baseIp = (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final hostBits = 32 - prefixLen;
    if (hostBits <= 8) {
      // /24 及更小：直接随机
      final hostMask = (1 << hostBits) - 1;
      final randomHost = rng.nextInt(hostMask - 1) + 1;
      return _intToIp((baseIp & ~hostMask) | randomHost);
    } else {
      // 更大的段：随机选一个 /24 子网，再从该子网随机取 IP
      final subnetBits = hostBits - 8;
      final randomSubnet = rng.nextInt(1 << subnetBits);
      final subnetBase = (baseIp & ~((1 << hostBits) - 1)) | (randomSubnet << 8);
      final randomHost = rng.nextInt(254) + 1; // 1-254
      return _intToIp(subnetBase | randomHost);
    }
  }

  static String _intToIp(int ip) {
    return '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}';
  }
}
