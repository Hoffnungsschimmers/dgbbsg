import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/notification_helper.dart';
import '../../app/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/net/endpoint.dart';
import '../../core/net/ip.dart';
import '../../core/net/proxy.dart';
import '../../core/net/http_fetcher.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 当前运行的动作类型。
enum RunAction { subscription, landing }

/// 落地检测进度（供运行页进度条/日志轮询展示）。
class LandingProgress {
  final int done;
  final int total;
  const LandingProgress(this.done, this.total);
}

/// 订阅器状态：含运行中标记、当前动作类型。
class SubscriptionsState {
  final bool running;
  final RunAction? currentAction;
  const SubscriptionsState({this.running = false, this.currentAction});
  SubscriptionsState copyWith({bool? running, RunAction? currentAction, bool clearAction = false}) =>
      SubscriptionsState(
        running: running ?? this.running,
        currentAction: clearAction ? null : (currentAction ?? this.currentAction),
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
      if (!mounted) return; // dispose 后不再启动定时器
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
    if (!mounted) return;
    if (!cfg.subAutoUpdateEnabled) return;
    final minutes = cfg.subAutoUpdateIntervalMin.clamp(5, 480);
    _autoUpdateTimer = Timer.periodic(Duration(minutes: minutes), (_) async {
      if (!mounted) return;
      final latestCfg = await _cfg();
      if (!mounted) return;
      if (!latestCfg.subAutoUpdateEnabled) {
        stopAutoUpdate();
        return;
      }
      final logger = ref.read(subLoggerProvider);
      logger.info('自动更新触发（间隔 ${latestCfg.subAutoUpdateIntervalMin} 分钟）');
      await runSubscription();
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
      final result = await convertSubscriptions(
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
      final nodes = result.nodes;
      if (_cancelRequested) {
        logger.info('「订阅IP」已取消');
      } else if (nodes.isEmpty) {
        if (result.failedSources > 0) {
          final msg = '「订阅IP」转换失败：全部 ${result.failedSources} 个订阅源均拉取失败或未解析出节点';
          logger.error(msg);
          NotificationHelper.taskFailed(taskName: '订阅IP转换', error: msg);
          _notifyWebhook(cfg, title: '订阅IP转换失败', body: msg, isError: true);
        } else {
          logger.warning('订阅转换无可用节点（请检查 subGenerators/subUrls 配置）');
        }
      } else {
        if (result.failedSources > 0) {
          logger.warning('部分订阅源失败：${result.okSources} 个成功，${result.failedSources} 个失败（见上方明细）');
        }
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

  Future<AppConfig> _cfg() => readLatestConfig(ref);

  /// 独立落地检测：对当前结果文件中的每个 IP 做 cdn-cgi/trace，
  /// 用真实 POP 覆盖国家码后写回落地输出文件（默认 `landingOutputFile`）。
  ///
  /// 流程语义（对应用户操作）：
  /// 1. 需要“开代理时的落地”→ 先开代理再点检测（经系统代理或配置的落地代理）；
  /// 2. 需要“当前网络直连落地”→ 关代理后点检测（强制直连）。
  /// [useProxy] 为 true 时经代理（优先配置的落地代理，否则系统代理），
  /// 为 false 时强制直连。返回 (成功数, 总数)。
  Future<(int, int)> runLandingCheck({required bool useProxy}) async {
    if (state.running) return (0, 0);
    _cancelRequested = false;
    state = state.copyWith(running: true, currentAction: RunAction.landing);
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    try {
      final resultState = ref.read(resultProvider);
      final currentFile = resultState.currentFile;
      String readPath;
      if (currentFile != null && currentFile.isNotEmpty && File(currentFile).existsSync()) {
        readPath = currentFile;
      } else {
        readPath = await _resolve(cfg.landingOutputFile);
      }
      final nodes = await _readNodes(readPath, logger: logger);
      if (nodes.isEmpty) {
        logger.warning('文件中未找到有效节点（$readPath），请先运行「订阅IP」。');
        return (0, 0);
      }
      // 落地检测只关心不重复的 IP（同 IP 多端口只查一次）。
      final ipOfNode = <String, String>{};
      for (final n in nodes) {
        final ep = parseEndpoint(n);
        if (ep != null) ipOfNode.putIfAbsent(ep.$1, () => n);
      }
      String? proxy;
      if (useProxy) {
        proxy = cfg.landingProxy.trim().isNotEmpty ? cfg.landingProxy.trim() : _systemProxy;
      }
      logger.info(useProxy
          ? '开始落地检测（经代理 ${proxy ?? '无可用代理，直连替代'}）：${ipOfNode.length} 个独立 IP'
          : '开始落地检测（直连，当前网络真实落地）：${ipOfNode.length} 个独立 IP');
      final landings = <String, String>{};
      final traceFailed = <String>[]; // trace 查不到落地的 IP（多为非 CF 直连 IP）
      var done = 0;
      for (final entry in ipOfNode.entries) {
        if (_cancelRequested) {
          logger.info('「落地检测」已取消');
          return (landings.length, ipOfNode.length);
        }
        final landing = await geolocateCfIp(
          entry.key,
          timeout: const Duration(milliseconds: 4000),
          proxy: proxy,
        ).timeout(const Duration(seconds: 12), onTimeout: () => null);
        done++;
        if (landing != null && landing.country.isNotEmpty) {
          landings[entry.key] = landing.country;
          logger.info('  [$done/${ipOfNode.length}] ${entry.key} → ${landing.airport}（${landing.country}）');
        } else if (landing != null) {
          logger.warning('  [$done/${ipOfNode.length}] ${entry.key} → 未知机场码 ${landing.airport}（已保留原标注）');
        } else {
          // 非 CF 边缘 IP 没有 cdn-cgi/trace 接口，先收集起来走归属地兜底。
          traceFailed.add(entry.key);
          logger.info('  [$done/${ipOfNode.length}] ${entry.key} → 非 CF 边缘，转查归属地…');
        }
      }

      // 兜底：trace 查不到的直连 IP（源站/IDC）按 IP 归属地识别落地国家。
      // 出口即服务器所在地，归属地即真实落地。先读本地缓存，未命中再批量查 ip-api.com。
      if (traceFailed.isNotEmpty && !_cancelRequested) {
        final cache = await _loadGeoCache();
        final needQuery = <String>[];
        for (final ip in traceFailed) {
          final cached = cache[ip];
          if (cached != null && cached.isNotEmpty) {
            landings[ip] = cached;
          } else {
            needQuery.add(ip);
          }
        }
        if (cache.isNotEmpty) {
          final hit = traceFailed.length - needQuery.length;
          if (hit > 0) logger.info('  归属地缓存命中 $hit 个');
        }
        if (needQuery.isNotEmpty) {
          logger.info('  批量查询 ${needQuery.length} 个 IP 的归属地（ip-api.com）…');
          final geo = await geolocateIpCountryBatch(needQuery, proxy: proxy);
          geo.forEach((ip, cc) {
            landings[ip] = cc;
            cache[ip] = cc;
          });
          await _saveGeoCache(cache);
          for (final ip in needQuery) {
            if (geo.containsKey(ip)) {
              logger.info('  归属地 $ip → ${geo[ip]}');
            } else {
              logger.warning('  归属地 $ip → 查询失败（已保留原标注）');
            }
          }
        }
      }

      if (landings.isEmpty) {
        logger.warning('落地检测完成：${ipOfNode.length} 个 IP 均未识别到落地，文件未改动。');
        return (0, ipOfNode.length);
      }
      // 用真实落地覆盖国家码后写回同一文件，并刷新结果页。
      final outPath = await _resolve(cfg.landingOutputFile);
      final updated = nodes.map((n) => applyRealLanding(n, landings)).toList();
      await writeSubOutput(updated, outPath);
      await ref.read(resultProvider.notifier).loadFile(outPath);
      // 按国家分组汇总，方便按国家/地区分类使用。
      final groups = <String, int>{};
      for (final n in updated) {
        final cc = nodeCountry(n);
        groups[cc.isEmpty ? '未知' : cc] = (groups[cc.isEmpty ? '未知' : cc] ?? 0) + 1;
      }
      final summary = groups.entries.map((e) => '${e.key}×${e.value}').join('、');
      logger.success('落地检测完成：${landings.length}/${ipOfNode.length} 个 IP 已更新 → $outPath（$summary）');
      _notifyWebhook(cfg, title: '落地检测完成', body: '${landings.length}/${ipOfNode.length} 个 IP 已更新（$summary）', isError: false);
      return (landings.length, ipOfNode.length);
    } finally {
      state = state.copyWith(running: false, clearAction: true);
    }
  }

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

  /// 归属地缓存文件路径（文档目录下 landing_geo_cache.json）。
  Future<File> _geoCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/landing_geo_cache.json');
  }

  /// 读取 IP → 国家码 归属地缓存。文件缺失/损坏时返回空表。
  Future<Map<String, String>> _loadGeoCache() async {
    try {
      final f = await _geoCacheFile();
      if (!f.existsSync()) return {};
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map) {
        return {
          for (final e in decoded.entries)
            if (e.value is String) e.key.toString(): e.value as String
        };
      }
    } catch (_) {
      // 缓存损坏时忽略，按空缓存处理
    }
    return {};
  }

  /// 写回 IP → 国家码 归属地缓存。失败静默（不影响主流程）。
  Future<void> _saveGeoCache(Map<String, String> cache) async {
    try {
      final f = await _geoCacheFile();
      await f.writeAsString(jsonEncode(cache));
    } catch (_) {
      // 写缓存失败不影响落地检测结果
    }
  }

  GithubPush? _github(AppConfig cfg) =>
      cfg.githubToken.isEmpty ? null : GithubPush(token: cfg.githubToken, repo: cfg.githubRepo, branch: cfg.githubBranch);

  /// 手动推送单个文件到 GitHub。返回 (是否成功, HTTP码, 消息)。
  /// 未配置 Token / 文件不存在时返回失败原因，不抛异常。
  Future<(bool, int, String)> pushFile(String file) async {
    if (!GithubPush.isPushable(file)) {
      final m = '仅支持推送后缀为 _top.txt 的落地结果文件（当前：$file）';
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
