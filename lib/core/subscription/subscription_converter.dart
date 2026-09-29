import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../config/app_config.dart';
import '../fetch/node_parser.dart';
import '../net/endpoint.dart';
import 'sub_parser.dart';

/// edgetunnel 系订阅器要求的 User-Agent（含项目特征串），用于触发
/// "优选订阅生成器(BEST_SUB)"模式并放行部分被 UA 拦截的实例。
const String edgetunnelUa = 'v2rayN/edgetunnel (https://github.com/cmliu/edgetunnel)';

/// 判断节点是否为垃圾/广告。
/// 常见模式：超长子域名（伪装成 Telegram 推广链接）、含推广关键词。
bool _isSpamNode(String host) {
  if (host.isEmpty) return false;
  // 子域名过长（正常域名一般 <50 字符）
  if (host.length > 60) return true;
  // 含推广关键词（不区分大小写）
  final lower = host.toLowerCase();
  const spamKeywords = [
    'telegram', 't.me', 'join', 'unlock', 'premium',
    'subscribe', 'channel', 'free', 'vip', '广告',
  ];
  for (final kw in spamKeywords) {
    if (lower.contains(kw)) return true;
  }
  return false;
}

/// 提不出国家码时的占位国家码：保证国家码位永远是两位码，原始名只出现在备注里，
/// 落地检测随后会用真实落地国家码覆盖它。
const String unknownCountryTag = 'UN';

/// 备注清洗：换行与连续空格压成一个。`#` 原样保留——行内只有第一个 `#` 是
/// 结构性的（国家码分隔符），解析侧一律按首个 `#` 切分，后续 `#` 不影响读取。
String _cleanRemark(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 原始节点名里已带来源名时剥掉，避免同一个名字在注释里出现两次。
/// 只在「整段相同 / 开头 / 结尾」三种形态下剥离，不做子串替换。
String _stripSourceDup(String remark, String source) {
  final s = source.trim();
  if (remark.isEmpty || s.isEmpty) return remark;
  final lowerRemark = remark.toLowerCase();
  final lowerSource = s.toLowerCase();
  if (lowerRemark == lowerSource) return '';
  if (lowerRemark.startsWith('$lowerSource ')) return remark.substring(s.length).trim();
  if (lowerRemark.endsWith(' $lowerSource')) {
    return remark.substring(0, remark.length - s.length - 1).trim();
  }
  return remark;
}

/// 解码订阅内容：若已是明文链接则原样返回，否则尝试 base64 解码。
String decodeSubscription(String text) {
  final t = text.trim();
  if (t.isEmpty) return '';
  if (t.contains('://')) return t;
  final decoded = SubParser.b64DecodeLoose(t);
  if (decoded != null && decoded.contains('://')) return decoded;
  return t;
}

/// 处理 sub://BASE64 形式的分享链接，解码出内部真实订阅地址。
/// 普通 http(s) 订阅地址原样返回。
String resolveSubUrl(String url) {
  final u = (url).trim();
  if (u.startsWith('sub://')) {
    final inner = SubParser.b64DecodeLoose(u.substring('sub://'.length).trim());
    if (inner != null) {
      final trimmed = inner.trim();
      if (trimmed.startsWith('http')) return trimmed;
    }
  }
  return u;
}

/// 把 "名称|域名" 或 "名称|域名|secret" 解析为 (name, host, secret)。
/// secret 为可选项：edgetunnel 部署的真实 uuid，或已算好的 token；
/// 提供后 [generatorFetchUrls] 会用它构造带鉴权的 /sub?token= 请求，
/// 以抓取"防范被抓取"的订阅器（如开启了 BEST_SUB 鉴权、未公开优选列表的实例）。
/// 仅写域名时 name=host，secret 为空。
(String, String, String) parseGenerator(String entry) {
  final e = (entry).trim();
  if (e.contains('|')) {
    final parts = e.split('|');
    final name = parts[0].trim();
    final host = parts[1].trim();
    final secret = parts.length > 2 ? parts[2].trim() : '';
    return (name, host, secret);
  }
  return (e, e, '');
}

/// edgetunnel /sub 的鉴权 token：md5(md5(host + userID))，host 与 userID 均小写。
/// 对应 worker 源码 `MD5MD5(host + userID)`（host 取请求域名，userID 为部署的 UUID）。
String edgetunnelToken(String host, String userID) {
  final s = '${host.trim().toLowerCase()}${userID.trim().toLowerCase()}';
  final inner = crypto.md5.convert(utf8.encode(s)).toString();
  return crypto.md5.convert(utf8.encode(inner)).toString();
}

bool _looksLikeUuid(String s) =>
    RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$')
        .hasMatch(s);

/// 为某个候选订阅器构造待尝试的拉取 URL（按优先级排列）。
/// 直连 URL（含路径）直接返回；否则依次尝试：
///   [secret 提供时] /sub?token=...  →
///   /sub?host=&uuid=（BEST_SUB 公开优选触发）→ /auto → /sub?token=auto。
/// [secret] 可选：edgetunnel 部署的真实 uuid 或已算好的 token。
/// 提供 uuid 时会按 worker 逻辑算 token = md5(md5(host + uuid))。
List<String> generatorFetchUrls(String host, AppConfig config, {String? secret}) {
  var h = host.trim();
  if (RegExp(r'^https?://[^/]+/.+').hasMatch(h)) return [h];
  if (h.startsWith('https://')) {
    h = h.substring('https://'.length);
  } else if (h.startsWith('http://')) {
    h = h.substring('http://'.length);
  }
  h = h.replaceAll(RegExp(r'/+$'), '');
  if (h.isEmpty) return [];

  final fakeHost = (config.subNodeHost.isNotEmpty ? config.subNodeHost : 'example.com').trim();
  final fakeUuid = (config.subNodeUuid.isNotEmpty
          ? config.subNodeUuid
          : '00000000-0000-0000-0000-000000000000')
      .trim();
  final base = 'https://$h';
  final qHost = Uri.encodeQueryComponent(fakeHost);
  final qUuid = Uri.encodeQueryComponent(fakeUuid);
  final urls = <String>[];
  // 带鉴权的 edgetunnel 部署：用 secret 构造 /sub?token= 请求，用于抓取防范被抓取的实例。
  if (secret != null && secret.isNotEmpty) {
    final token = _looksLikeUuid(secret) ? edgetunnelToken(h, secret) : secret;
    urls.add('$base/sub?token=${Uri.encodeQueryComponent(token)}');
  }
  // edgetunnel 仅暴露 /sub 端点（BEST_SUB 模式需 host+uuid 参数），/auto 不存在。
  urls.addAll([
    '$base/sub?host=$qHost&uuid=$qUuid',
    '$base/sub?token=auto',
  ]);
  return urls;
}

/// 收集订阅转换任务：[(来源名, [待尝试URL...]), ...]。
/// node 模式：逐个候选订阅器；url 模式：每个订阅链接为一项；both：两者合并。
List<(String, List<String>)> collectSubscriptionTasks(AppConfig config) {
  final mode = config.subInputMode.trim().toLowerCase();
  final tasks = <(String, List<String>)>[];

  if (mode == 'node' || mode == 'both') {
    final disabled = config.subDisabledGenerators;
    final gens = config.subGenerators
        .where((e) => e.trim().isNotEmpty)
        .map(parseGenerator)
        .where((g) => !(disabled.contains(g.$1) || disabled.contains(g.$2)))
        .toList();
    if (gens.isNotEmpty) {
      tasks.addAll(gens.map((g) => (
            g.$1.isNotEmpty ? g.$1 : g.$2,
            generatorFetchUrls(g.$2, config, secret: g.$3.isNotEmpty ? g.$3 : null),
          )));
    }
  }

  if (mode == 'url' || mode == 'both') {
    final disabled = config.subDisabledUrls;
    final urls = config.subUrls
        .where((u) => u.trim().isNotEmpty && !disabled.contains(u.trim()))
        .map((u) => u.trim())
        .toList();
    // 每个 URL 单独一项，提取 "标签|URL" 格式中的标签作为来源名。
    // 节点分享链接（supportedSchemes）本身不带标签；只有 http(s) 订阅地址
    // 支持标签前缀。用 scheme 精确判断，避免 "备注A|https://…" 被误判
    // 为无标签（它含 :// 但仍是带标签的订阅地址）。
    for (final url in urls) {
      var name = 'url';
      final pipeIdx = url.indexOf('|');
      if (pipeIdx > 0 && !supportedSchemes.any((s) => url.startsWith(s))) {
        name = url.substring(0, pipeIdx).trim();
      }
      tasks.add((name, [url]));
    }
  }
  return tasks;
}

/// 单个 URL 的拉取函数签名：返回订阅原文（sub:// 已解码；节点链接原样返回）。
/// [label] 为可选的日志标签（如订阅器名称）。
typedef SubFetcher = Future<String> Function(String url, {String label});

/// 拉取单个订阅链接/节点链接，返回其订阅原文。
/// - 支持的节点 scheme：直接返回（无需抓取）。
/// - sub:// 分享链接：先解码出内部地址再抓取。
/// - 其余 http(s)：正常抓取。
Future<String> fetchSingle(String url, SubFetcher fetch, {String label = ''}) async {
  // 去掉 "标签|URL" 格式中的标签前缀（如 "𝓜𝓲𝓪|https://..." → "https://..."）。
  // 节点分享链接直接返回；只有非节点链接才需要剥离标签（同样用 scheme
  // 精确判断，避免 "备注A|https://…" 被误判为节点链接而跳过剥离）。
  if (url.contains('|') && !supportedSchemes.any((s) => url.startsWith(s))) {
    final pipeIdx = url.indexOf('|');
    final after = url.substring(pipeIdx + 1).trim();
    if (after.isNotEmpty) url = after;
  }
  if (supportedSchemes.any((s) => url.startsWith(s))) return url;
  final real = resolveSubUrl(url);
  return fetch(real, label: label);
}

/// 逐个尝试候选 URL，返回第一个能解码出节点链接的订阅原文。
/// 找到即停（不浪费后续 URL 的重试时间），都没节点时返回首个非空兜底。
Future<String> fetchFirstWorking(List<String> urls, SubFetcher fetch, {void Function(String)? onLog, String label = ''}) async {
  if (urls.isEmpty) return '';
  String? fallback;
  for (final u in urls) {
    try {
      final content = await fetchSingle(u, fetch, label: label);
      if (content.isEmpty) continue;
      if (SubParser.parseSubscriptionLinks(decodeSubscription(content)).isNotEmpty) {
        return content; // 找到有效节点，立即返回，跳过剩余 URL
      }
      fallback ??= content;
    } on Exception catch (e) {
      onLog?.call('  [回退] $u 失败：$e');
    }
  }
  return fallback ?? '';
}

/// 转换所有候选订阅器/订阅链接为标准节点列表（只按 IP+端口去重）。
///
/// 输出行格式 `ip:port#国家码 来源名 原始节点备注`：国家码取自原始名，
/// 原始名里剩下的部分（地区/线路/编号等）作为备注保留在行尾；提不出国家码时
/// 用配置默认国家码，仍为空则写占位码 [unknownCountryTag]。
///
/// 返回记录：`nodes` 去重后的节点列表，`okSources` 解析出节点的源数，
/// `failedSources` 拉取失败或未解析出节点的源数，`okSourceNames` / `failedSourceNames`
/// 为对应来源名（供健康度统计；同一名字只要有一项成功就算成功）。
/// [fetch] 注入真实 HTTP 拉取；
/// [resolve] 注入域名解析（返回 IP 或 null）。[parser] 用于从节点名提取国家码。
Future<({
  List<String> nodes,
  int okSources,
  int failedSources,
  Set<String> okSourceNames,
  Set<String> failedSourceNames,
})> convertSubscriptions(
  AppConfig config, {
  required SubFetcher fetch,
  required Future<String?> Function(String host) resolve,
  required NodeParser parser,
  String? proxy,
  void Function(String)? onLog,
}) async {
  final tasks = collectSubscriptionTasks(config);
  if (tasks.isEmpty) {
    return (
      nodes: <String>[],
      okSources: 0,
      failedSources: 0,
      okSourceNames: <String>{},
      failedSourceNames: <String>{},
    );
  }

  final rawNodes = <({String host, int port, String name, String source})>[];
  final okSourceNames = <String>{};
  final failedSourceNames = <String>{};
  var okSources = 0;
  var failedSources = 0;

    for (final (name, urls) in tasks) {
      onLog?.call('━━━ $name ━━━');
      final bodies = name == 'url'
          ? await Future.wait(urls.map((u) => fetchSingle(u, fetch, label: name)))
          : [await fetchFirstWorking(urls, fetch, onLog: onLog, label: name)];

      var got = 0;
      var bodySucceeded = 0;
      for (final content in bodies) {
        if (content.isEmpty) continue;
        // 优先按 vless/vmess 订阅格式解析
        final parsed = SubParser.parseSubscriptionLinks(decodeSubscription(content));
        if (parsed.isNotEmpty) {
          bodySucceeded++;
          got += parsed.length;
          for (final p in parsed) {
            rawNodes.add((host: p.host, port: p.port, name: p.name, source: name));
          }
        } else {
          // 回退：按纯 IP/域名 列表解析（如 bestcf.pages.dev 的 txt 文件）
          final textNodes = parser.parseTextNodesWithRemark(content);
          if (textNodes.isNotEmpty) bodySucceeded++;
          got += textNodes.length;
          for (final node in textNodes) {
            // 有标签但提不出国家码的行按原行为丢弃。
            if (node.cc.isEmpty && node.remark.isNotEmpty) continue;
            final ep = parseEndpoint(node.ipPort);
            if (ep == null) continue;
            // 拼成「国家码 原始备注」，与协议链接的原始名走同一套拆分逻辑。
            final label = node.cc.isEmpty
                ? node.remark
                : '${node.cc} ${node.remark}'.trim();
            rawNodes.add((host: ep.$1, port: ep.$2, name: label, source: name));
          }
        }
      }
      if (bodySucceeded > 0) {
        okSources++;
        okSourceNames.add(name);
        onLog?.call('[+] $name 解析出 $got 个节点。');
      } else {
        failedSources++;
        failedSourceNames.add(name);
        onLog?.call('[-] $name：所有 URL 均拉取失败或未解析出节点。');
      }
    }

  if (rawNodes.isEmpty) {
    return (
      nodes: <String>[],
      okSources: okSources,
      failedSources: failedSources,
      okSourceNames: okSourceNames,
      failedSourceNames: failedSourceNames,
    );
  }

  final hosts = <String>{for (final r in rawNodes) r.host};
  final resolved = <String, String?>{};
  if (config.subResolveDomain) {
    await Future.wait(hosts.map((h) async {
      resolved[h] = await resolve(h);
    }));
  } else {
    for (final h in hosts) {
      resolved[h] = h;
    }
  }

  // 组装节点列表：默认国家码兜底 + 只按 ip:port 去重。
  // 同一 IP+端口只保留首次出现（国家码/来源标注不同也不保留多条）；
  // 不同端口视为不同节点保留。
  // 注释格式：`#国家码 来源名 原始节点备注`。
  final defaultCc = config.subDefaultCountry.trim().toUpperCase();
  final nodes = <String>[];
  final seenIpPort = <String>{};
  for (final r in rawNodes) {
    final ip = resolved[r.host];
    if (ip == null || ip.isEmpty) continue;
    if (_isSpamNode(r.host)) continue;
    // 去重键只看 ip:port（归一小写后比较），国家码/来源不同也不保留多条。
    if (!seenIpPort.add('${ip.toLowerCase()}:${r.port}')) continue;
    // IPv6 需要方括号包裹
    final addr = ip.contains(':') ? '[$ip]' : ip;
    // 标准化国家码（中文名/三字母码 → 两位码），原始名中剩余部分留作备注；
    // 提不出国家码时用配置的默认国家码兜底，仍没有则用占位码 UN
    // （避免原始名挤进国家码位，落地检测会把它换成真实落地码）。
    final split = parser.splitLabel(r.name.trim());
    final remark = _stripSourceDup(_cleanRemark(split.remark), r.source);
    final tag = split.cc ?? (defaultCc.isNotEmpty ? defaultCc : unknownCountryTag);
    nodes.add([
      tag.isNotEmpty ? '$addr:${r.port}#$tag' : '$addr:${r.port}',
      r.source,
      if (remark.isNotEmpty && remark != tag) remark,
    ].join(' ').trimRight());
  }

  onLog?.call('订阅获取完成：成功 $okSources 个源，失败 $failedSources 个源，共 ${rawNodes.length} 个节点，输出 ${nodes.length} 个。');
  return (
    nodes: nodes,
    okSources: okSources,
    failedSources: failedSources,
    okSourceNames: okSourceNames,
    failedSourceNames: failedSourceNames,
  );
}

/// 将订阅转换结果写入独立文件（LF 换行，便于 git 处理）。
/// 同时写入 .json 旁文件记录生成时间和节点数。
Future<void> writeSubOutput(List<String> nodes, String outputFile) async {
  final f = File(outputFile);
  await f.create(recursive: true);
  final sink = f.openWrite(encoding: utf8, mode: FileMode.writeOnly);
  for (final node in nodes) {
    sink.write('$node\n');
  }
  await sink.flush();
  await sink.close();

  // 写入 .json 旁文件（生成时间 + 节点数）
  final ts = DateTime.now().toString().substring(0, 19);
  final jsonFile = File('${f.path}.json');
  await jsonFile.writeAsString(jsonEncode({
    'generated_at': ts,
    'node_count': nodes.length,
  }));
}
