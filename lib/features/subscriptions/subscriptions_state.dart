import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/motion.dart';
import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/latency/latency_filter.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/net/ip.dart';
import '../../core/net/proxy.dart';
import '../../core/net/retry.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 走 Dio 带 cfg 化超时与指数退避重试的 HTTP GET，返回 body 明文。
///
/// 成功响应 (status 200-299) 直接返回 `.data.toString()`；其它状态码被 Dio
/// 默认的 `validateStatus` 判定并转换成 [dio_pkg.DioException]，由
/// [retry] 捕获并触发下一次尝试。
///
/// - 三档超时 (`connectTimeout`/`sendTimeout`/`receiveTimeout`) 与 `maxRetries`
///   由调用方从 [AppConfig] 注入；本函数只在内部做 `clamp` 防御非法值。
/// - `sleep` 默认为 [Future.delayed]；测试可注入 mock 以跳过真实指数退避。
/// - `maxRetries` 语义：`0` 表示不重试（只走第一次），与 [retry] 一致。
Future<String> fetchHttpWithRetry({
  required dio_pkg.Dio dio,
  required String url,
  required int connectTimeoutSec,
  required int sendTimeoutSec,
  required int receiveTimeoutSec,
  required int maxRetries,
  required int retryDelayMs,
  Future<void> Function(Duration)? sleep,
  void Function(String)? onLog,
}) async {
  Future<String> doGet() async {
    final resp = await dio.get<String>(
      url,
      options: dio_pkg.Options(
        responseType: dio_pkg.ResponseType.plain,
        headers: const {
          'User-Agent': edgetunnelUa,
          'Accept': '*/*',
        },
        connectTimeout: Duration(seconds: connectTimeoutSec.clamp(1, 300)),
        sendTimeout: Duration(seconds: sendTimeoutSec.clamp(1, 600)),
        receiveTimeout: Duration(seconds: receiveTimeoutSec.clamp(1, 600)),
      ),
    );
    return resp.data.toString();
  }

  final retries = maxRetries.clamp(0, 10);
  return retry<String>(
    doGet,
    maxRetries: retries,
    initialDelay: Duration(milliseconds: retryDelayMs),
    sleep: sleep,
    onRetry: retries > 0
        ? (attempt, max, error, delay) {
            onLog?.call('  ↻ 重试 $attempt/$max（${classifyFetchError(error, url)}，'
                '${(delay.inMilliseconds / 1000).toStringAsFixed(1)}s 后重试）');
          }
        : null,
  );
}

/// 把抓取异常分类为可读提示（供日志/排障）。纯函数。
String classifyFetchError(Object e, String url) {
  if (e is dio_pkg.DioException) {
    final t = e.type;
    if (t == dio_pkg.DioExceptionType.connectionTimeout ||
        t == dio_pkg.DioExceptionType.sendTimeout) {
      return '连接超时（源不可达或被墙）';
    }
    if (t == dio_pkg.DioExceptionType.receiveTimeout) {
      return '读取超时（响应过慢）';
    }
    if (t == dio_pkg.DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      final hint = (code == 403 && url.contains('/sub'))
          ? '（该 edgetunnel 部署可能未启用 BEST_SUB：请在 Cloudflare 变量设置 BEST_SUB=1）'
          : '';
      return 'HTTP ${code ?? '?'} 错误$hint';
    }
    if (t == dio_pkg.DioExceptionType.connectionError) {
      return '连接失败（DNS/网络不可达）';
    }
    // 检查底层异常：TLS 握手失败 / 证书错误
    final inner = e.error;
    if (inner is HandshakeException) {
      final msg = inner.message;
      if (msg.contains('CERTIFICATE_VERIFY_FAILED')) {
        return 'TLS 证书校验失败（域名与证书不匹配或证书不受信，可尝试开启「跳过 TLS 证书校验」）';
      }
      if (msg.contains('HANDSHAKE_FAILURE') || msg.contains('SSLV3_ALERT')) {
        return 'TLS 握手失败（服务端不兼容当前 TLS 版本/密码套件）';
      }
      return 'TLS 握手异常：$msg';
    }
    if (inner is SocketException) {
      return '网络连接失败：${inner.message}';
    }
    return '请求异常：${e.message ?? e}';
  }
  return '未知错误：$e';
}

/// 当前运行的动作类型。
enum RunAction { subscription, latency }

/// 延迟优选的细粒度进度。
class LatencyProgress {
  final int done;
  final int total;
  final int connected;
  final int eliminated;
  const LatencyProgress({required this.done, required this.total, required this.connected, required this.eliminated});
  double get percent => total == 0 ? 0 : done / total;
  LatencyProgress copyWith({int? done, int? total, int? connected, int? eliminated}) =>
      LatencyProgress(
        done: done ?? this.done,
        total: total ?? this.total,
        connected: connected ?? this.connected,
        eliminated: eliminated ?? this.eliminated,
      );
}

/// 延迟优选完成后的结果摘要（供 RunTab 显示 3 秒后自动消失）。
class LatencySummary {
  final int tested;
  final int connected;
  final int kept;
  const LatencySummary({required this.tested, required this.connected, required this.kept});
}

/// 订阅器状态：含运行中标记、当前动作类型、延迟优选进度。
class SubscriptionsState {
  final bool running;
  final LatencyProgress? progress;
  final RunAction? currentAction;
  final LatencySummary? lastResult;
  SubscriptionsState({this.running = false, this.progress, this.currentAction, this.lastResult});
  SubscriptionsState copyWith({bool? running, LatencyProgress? progress, bool clearProgress = false, RunAction? currentAction, bool clearAction = false, LatencySummary? lastResult, bool clearResult = false}) =>
      SubscriptionsState(
        running: running ?? this.running,
        progress: clearProgress ? null : (progress ?? this.progress),
        currentAction: clearAction ? null : (currentAction ?? this.currentAction),
        lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      );
}

class SubscriptionsNotifier extends StateNotifier<SubscriptionsState> {
  final Ref ref;

  /// 取消标志：调用 [cancel] 后置 true，任务在下一个检查点退出。
  bool _cancelRequested = false;

  /// 强制停止当前运行的任务。
  void cancel() {
    _cancelRequested = true;
  }

  /// Windows 系统代理地址（如 '127.0.0.1:10808'），无代理时为空。
  static final String? _systemProxy = readWindowsSystemProxy();

  /// 长生命周期安全 Dio（走系统代理、校验 TLS 证书）。
  final dio_pkg.Dio _dioSafe = GithubPush.directDio();

  /// 长生命周期跳过证书校验的 Dio（自签名/过期证书源）。
  /// 注意：validateStatus 保持默认（非 2xx 抛异常），仅跳过 TLS 证书校验，
  /// 以便 HTTP 错误仍能触发 retry 机制。代理配置从 _dioSafe 复用。
  late final dio_pkg.Dio _dioInsecure = (() {
    final d = GithubPush.directDio();
    // 复用 _dioSafe 的代理配置（directDio 已自动读取 Windows 系统代理）
    final adapter = d.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      final safeAdapter = _dioSafe.httpClientAdapter;
      if (safeAdapter is IOHttpClientAdapter && safeAdapter.createHttpClient != null) {
        final safeFactory = safeAdapter.createHttpClient!;
        adapter.createHttpClient = () {
          final client = safeFactory();
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      } else {
        adapter.createHttpClient = () {
          return HttpClient()..badCertificateCallback = (_, _, _) => true;
        };
      }
    }
    return d;
  })();

  SubscriptionsNotifier(this.ref) : super(SubscriptionsState());

  /// 单独：订阅IP（转换订阅器 -> addressesapi.txt）。
  Future<void> runSubscription() async {
    if (state.running) return;
    _cancelRequested = false;
    state = state.copyWith(running: true, currentAction: RunAction.subscription);
    final cfg = await _cfg();
    final parser = await ref.read(nodeParserProvider.future);
    final logger = ref.read(subLoggerProvider);
    logger.info('开始「订阅IP」转换…');
    try {
      final nodes = await convertSubscriptions(
        cfg,
        fetch: (url, {label = ''}) {
          if (_cancelRequested) return Future.value('');
          return _safeFetch(url, cfg.subInsecure, cfg, label: label);
        },
        resolve: _resolveHost,
        parser: parser,
        proxy: _systemProxy,
        onLog: (m) => logger.info(m),
      );
      if (_cancelRequested) {
        logger.info('「订阅IP」已取消');
      } else if (nodes.isEmpty) {
        logger.warning('订阅转换无可用节点（请检查 subGenerators/subUrls 配置）');
      } else {
        final outPath = await _resolve(cfg.subOutputFile);
        await writeSubOutput(nodes, outPath);
        await ref.read(resultProvider.notifier).loadFile(outPath);
        logger.success('订阅IP转换完成：${nodes.length} 个节点 -> $outPath');
      }
    } catch (e) {
      logger.error(e.toString());
    } finally {
      state = state.copyWith(running: false, clearAction: true);
    }
  }

  /// 单独：延迟优选（对订阅IP做延迟测试，保留前 N 名 -> addressesapi_top.txt）。
  Future<void> runLatency() async {
    if (state.running) return;
    _cancelRequested = false;
    state = state.copyWith(running: true, currentAction: RunAction.latency);
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    logger.info('开始「延迟优选」');

    // 进度节流：缓存最新值，每 60ms flush 一次到 state，避免高频 setState 风暴。
    LatencyProgress? latestProgress;
    Timer? progressTimer;
    void scheduleFlush() {
      progressTimer ??= Timer(Motion.throttleTick, () {
        progressTimer = null;
        if (latestProgress != null) {
          state = state.copyWith(progress: latestProgress);
        }
        if (latestProgress != null && latestProgress!.done < latestProgress!.total) {
          scheduleFlush();
        }
      });
    }

    try {
      final nodes = await _readNodes(await _resolve(cfg.subOutputFile));
      if (nodes.isEmpty) {
        logger.warning('未找到订阅IP文件（${cfg.subOutputFile}），请先运行「订阅IP」');
      } else {
        final latencyOut = await _resolve(cfg.subLatencyOutputFile);
        final (kept, tested, connected) = await LatencyFilter.run(
          nodes: nodes,
          outputFile: latencyOut,
          latencyMaxMs: cfg.subLatencyMaxMs,
          timeout: Duration(milliseconds: (cfg.subLatencyTimeout * 1000).round()),
          workers: cfg.subLatencyWorkers,
          probes: cfg.subLatencyProbes,
          minSuccessRate: cfg.subLatencyMinSuccessRate,
          topN: cfg.subLatencyTopN > 0 ? cfg.subLatencyTopN : 100000,
          probe: measureLatency,
          onLog: (m) => logger.info(m),
          isCancelled: () => _cancelRequested,
          onProgress: (done, total, conn) {
            latestProgress = LatencyProgress(
              done: done,
              total: total,
              connected: conn,
              eliminated: done - conn,
            );
            scheduleFlush();
          },
        );
        // 最终 flush
        progressTimer?.cancel();
        if (latestProgress != null) {
          state = state.copyWith(progress: latestProgress);
        }
        if (_cancelRequested) {
          logger.info('延迟优选已取消（已完成 $tested 个探测）');
        } else {
          logger.success('延迟优选完成：测试 $tested / 连通 $connected / 保留 ${kept.length}');
        }
        state = state.copyWith(lastResult: LatencySummary(tested: tested, connected: connected, kept: kept.length));
        await ref.read(resultProvider.notifier).loadFile(latencyOut);
      }
    } catch (e) {
      logger.error(e.toString());
    } finally {
      progressTimer?.cancel();
      state = state.copyWith(running: false, clearProgress: true, clearAction: true);
    }
  }

  Future<AppConfig> _cfg() async {
    final repo = await ref.read(configRepositoryProvider.future);
    return repo.current;
  }

  Future<String> _resolve(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return resolveOutputPath(name, dir.path);
  }

  GithubPush? _github(AppConfig cfg) =>
      cfg.githubToken.isEmpty ? null : GithubPush(token: cfg.githubToken, repo: cfg.githubRepo, branch: cfg.githubBranch);

  /// 手动推送单个产物文件到 GitHub（cf-ip 仓）。返回 (是否成功, HTTP码, 消息)。
  /// 未配置 Token / 文件不存在时返回失败原因，不抛异常。
  Future<(bool, int, String)> pushFile(String file) async {
    if (!GithubPush.isPushable(file)) {
      final m = '仅支持推送后缀为 _top.txt 的优选结果文件（当前：$file）';
      ref.read(subLoggerProvider).warning(m);
      return (false, 0, m);
    }
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    final github = _github(cfg);
    if (github == null) {
      final m = 'GitHub 未配置（请在设置填写 Token/Repo/Branch），跳过推送：$file';
      logger.warning(m);
      return (false, 0, m);
    }
    // 解析为绝对路径（文件写入文档目录，相对路径需拼接）
    final resolved = await _resolve(file);
    if (!File(resolved).existsSync()) {
      final m = '文件不存在：$resolved';
      logger.error(m);
      return (false, 0, m);
    }
    try {
      final content = await File(resolved).readAsString();
      logger.info('开始推送 $file 到 GitHub（${cfg.githubRepo}@${cfg.githubBranch}）…');
      final code = await github.pushFile(file, content, message: 'update $file');
      logger.success('已推送 $file (HTTP $code)');
      return (true, code, '已推送 $file (HTTP $code)');
    } catch (e) {
      final m = '推送 $file 失败：$e';
      logger.error(m);
      return (false, 0, m);
    }
  }

  // ---- 网络辅助 ----
  // 订阅源抓取共用顶层函数 [fetchHttpWithRetry]。`_dioSafe` 走系统代理并校验
  // TLS 证书，`_dioInsecure` 跳过证书校验以兼容自签/过期证书源。两个 Dio 均为
  // 长生命周期实例，复用 TCP 连接（keep-alive）。

  /// 容错抓取：失败按 [AppConfig] 重试到耗尽，最终失败仅记录并返回空串，
  /// 不中断整体转换。多候选 URL 的回退在 convertSubscriptions 内处理。
  /// [label] 为日志前缀（如订阅器名称），便于区分并发日志归属。
  Future<String> _safeFetch(String url, bool certInsecure, AppConfig cfg, {String label = ''}) async {
    final logger = ref.read(subLoggerProvider);
    final dio = certInsecure ? _dioInsecure : _dioSafe;
    final tag = label.isNotEmpty ? '[$label] ' : '';
    logger.info('$tag→ 请求 $url');
    try {
      final content = await fetchHttpWithRetry(
        dio: dio,
        url: url,
        connectTimeoutSec: cfg.subFetchConnectTimeout,
        sendTimeoutSec: cfg.subFetchTimeout,
        receiveTimeoutSec: cfg.subFetchTimeout,
        maxRetries: cfg.subFetchMaxRetries.clamp(0, 10),
        retryDelayMs: (cfg.subFetchRetryDelay * 1000).round(),
        onLog: (m) {
          // 重试消息语义为警告，其余保持 info
          if (m.contains('↻ 重试')) {
            logger.warning('$tag$m');
          } else {
            logger.info('$tag$m');
          }
        },
      );
      final len = content.length;
      logger.success('$tag✓ 成功（${len > 100 ? '$len 字符' : len > 0 ? '内容 $len 字符' : '空响应'}）');
      return content;
    } catch (e) {
      logger.error('$tag✗ 失败：${classifyFetchError(e, url)}');
      return '';
    }
  }

  Future<String?> _resolveHost(String host) async {
    if (isIp(host)) return host;
    try {
      final list = await InternetAddress.lookup(host);
      return list.isNotEmpty ? list.first.address : null;
    } on Object {
      return null;
    }
  }

  Future<List<String>> _readNodes(String path) async {
    final f = File(path);
    if (!f.existsSync()) return [];
    final text = await f.readAsString();
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
  }

}

final subProvider = StateNotifierProvider<SubscriptionsNotifier, SubscriptionsState>(
    (ref) => SubscriptionsNotifier(ref));
