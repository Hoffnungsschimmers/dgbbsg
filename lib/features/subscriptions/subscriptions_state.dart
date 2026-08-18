import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/motion.dart';
import '../../app/notification_helper.dart';
import '../../app/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/latency/latency_filter.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/net/ip.dart';
import '../../core/net/proxy.dart';
import '../../core/net/http_fetcher.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

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

  /// 自动更新定时器。
  Timer? _autoUpdateTimer;

  /// 强制停止当前运行的任务。
  void cancel() {
    _cancelRequested = true;
  }

  /// 系统代理地址（如 '127.0.0.1:10808'），无代理时为空。
  static String? get _systemProxy => readSystemProxy();

  /// 长生命周期安全 Dio（走系统代理、校验 TLS 证书）。
  final dio_pkg.Dio _dioSafe = GithubPush.directDio();

  /// 长生命周期跳过证书校验的 Dio（自签名/过期证书源，对应 subInsecure）。
  /// 注意：validateStatus 保持默认（非 2xx 抛异常），仅跳过 TLS 证书校验，
  /// 以便 HTTP 错误仍能触发 retry 机制。代理配置从 _dioSafe 复用。
  final dio_pkg.Dio _dioInsecure = GithubPush.directDio(insecure: true);

  SubscriptionsNotifier(this.ref) : super(SubscriptionsState()) {
    // 配置加载后启动自动更新定时器（如果已启用）。
    _initAutoUpdate();
  }

  /// 异步初始化自动更新：等待配置仓库就绪后按需启动定时器。
  Future<void> _initAutoUpdate() async {
    try {
      final cfg = await _cfg();
      if (cfg.subAutoUpdateEnabled) {
        startAutoUpdate();
      }
    } catch (_) {
      // 配置加载失败时静默忽略，不影响主流程。
    }
  }

  /// 启动自动更新定时器。若已存在则先取消再重建。
  Future<void> startAutoUpdate() async {
    stopAutoUpdate();
    final cfg = await _cfg();
    if (!cfg.subAutoUpdateEnabled) return;
    final minutes = cfg.subAutoUpdateIntervalMin.clamp(5, 480);
    _autoUpdateTimer = Timer.periodic(Duration(minutes: minutes), (_) async {
      final latestCfg = await _cfg();
      if (!latestCfg.subAutoUpdateEnabled) {
        stopAutoUpdate();
        return;
      }
      final logger = ref.read(subLoggerProvider);
      logger.info('自动更新触发（间隔 ${latestCfg.subAutoUpdateIntervalMin} 分钟）');
      await runSubscription();
      if (latestCfg.subAutoUpdateRunLatency) {
        await runLatency();
      }
    });
  }

  /// 停止自动更新定时器。
  void stopAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
  }

  @override
  void dispose() {
    stopAutoUpdate();
    super.dispose();
  }

  /// 一键运行：先订阅转换，再延迟优选。
  Future<void> runAll() async {
    await runSubscription();
    if (!_cancelRequested && !state.running) {
      await runLatency();
    }
  }

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
        NotificationHelper.taskComplete(taskName: '订阅IP转换', summary: '${nodes.length} 个节点已保存');
        _notifyWebhook(cfg, title: '订阅IP转换完成', body: '${nodes.length} 个节点已保存 -> $outPath', isError: false);
      }
    } catch (e) {
      logger.error(e.toString());
      NotificationHelper.taskFailed(taskName: '订阅IP转换', error: e.toString());
      _notifyWebhook(cfg, title: '订阅IP转换失败', body: e.toString(), isError: true);
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
      // 优先使用 Results 标签页已加载的文件；否则回退到配置的输出文件。
      final resultState = ref.read(resultProvider);
      final currentFile = resultState.currentFile;
      String readPath;
      if (currentFile != null && currentFile.isNotEmpty && File(currentFile).existsSync()) {
        readPath = currentFile;
        logger.info('使用当前已加载的文件：$readPath');
      } else {
        readPath = await _resolve(cfg.subOutputFile);
        logger.info('使用配置的输出文件：$readPath');
      }
      final nodes = await _readNodes(readPath, logger: logger);
      if (nodes.isEmpty) {
        logger.warning('文件中未找到有效节点（$readPath）。'
            '请确认文件格式为 ip:port#CC（每行一个），或先运行「订阅IP」生成。');
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
          NotificationHelper.taskComplete(
            taskName: '延迟优选完成',
            summary: '测试 $tested / 连通 $connected / 保留 ${kept.length}',
          );
          _notifyWebhook(cfg, title: '延迟优选完成', body: '测试 $tested / 连通 $connected / 保留 ${kept.length}', isError: false);
        }
        state = state.copyWith(lastResult: LatencySummary(tested: tested, connected: connected, kept: kept.length));
        await ref.read(resultProvider.notifier).loadFile(latencyOut);
      }
    } catch (e) {
      logger.error(e.toString());
      _notifyWebhook(cfg, title: '延迟优选失败', body: e.toString(), isError: true);
    } finally {
      progressTimer?.cancel();
      state = state.copyWith(running: false, clearProgress: true, clearAction: true);
    }
  }

  Future<AppConfig> _cfg() => readLatestConfig(ref);

  /// 发送 Webhook 通知（若已配置）。静默失败，不影响主流程。
  Future<void> _notifyWebhook(AppConfig cfg, {required String title, required String body, required bool isError}) async {
    if (cfg.webhookType == 'none' || cfg.webhookUrl.isEmpty) return;
    if (isError && !cfg.webhookOnError) return;
    if (!isError && !cfg.webhookOnComplete) return;
    try {
      final sender = ref.read(webhookSenderProvider);
      await sender.send(
        type: cfg.webhookType,
        url: cfg.webhookUrl,
        title: title,
        body: body,
      );
    } catch (_) {
      // 通知失败不影响主流程
    }
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

  Future<List<String>> _readNodes(String path, {AppLogger? logger}) async {
    final f = File(path);
    if (!f.existsSync()) {
      logger?.warning('文件不存在：$path');
      return [];
    }
    final text = await f.readAsString();
    if (text.isEmpty) {
      logger?.warning('文件内容为空：$path');
      return [];
    }
    final lines = text.split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
    logger?.info('读取 ${lines.length} 行节点数据（$path）');
    return lines;
  }

}

final subProvider = StateNotifierProvider<SubscriptionsNotifier, SubscriptionsState>((ref) {
  final notifier = SubscriptionsNotifier(ref);
  // 监听配置变化，自动启停自动更新定时器。
  ref.listen<AsyncValue<AppConfig>>(configProvider, (_, next) {
    next.whenData((cfg) {
      if (cfg.subAutoUpdateEnabled) {
        notifier.startAutoUpdate();
      } else {
        notifier.stopAutoUpdate();
      }
    });
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});
