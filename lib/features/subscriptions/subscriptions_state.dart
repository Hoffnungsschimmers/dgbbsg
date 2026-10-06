import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/notification_helper.dart';
import '../../app/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/net/egress_compare.dart';
import '../../core/net/endpoint.dart';
import '../../core/net/ip.dart';
import '../../core/net/landing_history.dart';
import '../../core/net/proxy.dart';
import '../../core/net/http_fetcher.dart';
import '../../core/net/task_cancel.dart';
import '../../core/net/push_quality.dart';
import '../../core/net/geo_cache.dart';
import '../../core/storage/result_files.dart';
import '../../core/storage/safe_file.dart';
import '../../core/subscription/source_health.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 当前运行的动作类型。
enum RunAction { subscription, landing, pipeline, egressCompare }

/// Network probes are injectable so pipeline failure/cancellation can be
/// verified without contacting real subscription services or GitHub.
final landingProbeProvider = Provider<Future<CfLanding?> Function(String, TaskCancel)>((ref) =>
  (ip, cancel) => geolocateCfIp(ip, timeout: const Duration(seconds: 4), cancel: cancel));
final egressProbeProvider = Provider<Future<EgressInfo?> Function(TaskCancel)>((ref) =>
  (cancel) => probeEgress(cancel: cancel));
final geoProbeProvider = Provider<Future<Map<String, String>> Function(List<String>, TaskCancel)>((ref) =>
  (ips, cancel) => geolocateIpCountryBatch(ips, cancel: cancel));
final subscriptionDioProvider = Provider<dio_pkg.Dio Function(bool)>((ref) =>
  (insecure) => GithubPush.directDio(insecure: insecure));

/// 订阅器状态：含运行中标记、当前动作类型。
class SubscriptionsState {
  final bool running;
  final RunAction? currentAction;
  final String stage;
  final int done;
  final int total;
  final String summary;
  final bool succeeded;
  const SubscriptionsState({this.running = false, this.currentAction,
    this.stage = '', this.done = 0, this.total = 0, this.summary = '', this.succeeded = false});
  SubscriptionsState copyWith({bool? running, RunAction? currentAction, bool clearAction = false,
    String? stage, int? done, int? total, String? summary, bool? succeeded}) =>
      SubscriptionsState(
        running: running ?? this.running,
        currentAction: clearAction ? null : (currentAction ?? this.currentAction),
        stage: stage ?? this.stage, done: done ?? this.done, total: total ?? this.total,
        summary: summary ?? this.summary, succeeded: succeeded ?? this.succeeded,
      );
}

class SubscriptionsNotifier extends StateNotifier<SubscriptionsState> {
  final Ref ref;

  /// 取消标志：调用 [cancel] 后置 true，任务在下一个检查点退出。
  bool _cancelRequested = false;

  /// 正在跑 [runPipeline] 时为 true：单步动作此时不自管 running 状态，
  /// 否则它们会互相把对方的 running 标志清掉。
  bool _inPipeline = false;
  AppConfig? _runConfig;
  TaskCancel _cancel = TaskCancel();
  dio_pkg.CancelToken _dioCancel = dio_pkg.CancelToken();
  int _measured = 0;
  int _estimated = 0;
  int _previousNodes = 0;
  String _outcome = '';
  bool _success = false;
  bool _pushDispatched = false;
  DateTime? _started;

  void _begin(RunAction action) {
    _cancelRequested = false;
    _cancel = TaskCancel();
    _dioCancel = dio_pkg.CancelToken();
    _cancel.register(() => _dioCancel.cancel('任务已取消'));
    _runConfig = null;
    _measured = 0;
    _estimated = 0;
    _previousNodes = 0;
    _outcome = '';
    _success = false;
    _pushDispatched = false;
    _started = DateTime.now();
    state = SubscriptionsState(running: true, currentAction: action);
  }

  void _progress(String stage, [int done = 0, int total = 0]) {
    if (mounted && state.running && (!_cancelRequested || stage == '正在取消…')) {
      state = state.copyWith(stage: stage, done: done, total: total);
    }
  }

  void _finish() {
    if (!mounted) return;
    final seconds = _started == null ? 0 : DateTime.now().difference(_started!).inSeconds;
    final summary = _cancelRequested ? (_pushDispatched
        ? '已取消；已提交的推送可能已在远端完成，请检查远端结果'
        : '已取消；未推送未完成结果') :
        (_outcome.isEmpty ? '任务未完成，详见日志' : _outcome);
    state = state.copyWith(running: false, clearAction: true,
        summary: '$summary · 耗时 $seconds 秒', succeeded: _success && !_cancelRequested);
    _runConfig = null;
  }

  /// 自动更新定时器。
  Timer? _autoUpdateTimer;
  int _autoTimerGeneration = 0;

  /// 强制停止当前运行的任务。
  void cancel() {
    _cancelRequested = true;
    _cancel.cancel();
    _progress('正在取消…');
  }

  /// 系统代理地址（如 '127.0.0.1:10808'），无代理时为空。
  static String? get _systemProxy => readSystemProxy();

  /// 长生命周期安全 Dio（走系统代理、校验 TLS 证书）。
  late final dio_pkg.Dio _dioSafe;

  /// 长生命周期跳过证书校验的 Dio（自签名/过期证书源，对应 subInsecure）。
  /// 注意：validateStatus 保持默认（非 2xx 抛异常），仅跳过 TLS 证书校验，
  /// 以便 HTTP 错误仍能触发 retry 机制。代理配置从 _dioSafe 复用。
  late final dio_pkg.Dio _dioInsecure;

  SubscriptionsNotifier(this.ref) : super(SubscriptionsState()) {
    _dioSafe = ref.read(subscriptionDioProvider)(false);
    _dioInsecure = ref.read(subscriptionDioProvider)(true);
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
    final generation = _autoTimerGeneration;
    final cfg = await _cfg();
    if (!mounted || generation != _autoTimerGeneration) return;
    if (!cfg.subAutoUpdateEnabled) return;
    final minutes = cfg.subAutoUpdateIntervalMin.clamp(5, 720);
    _autoUpdateTimer = Timer.periodic(Duration(minutes: minutes), (_) => unawaited(runScheduledUpdate()));
  }

  Future<void> runScheduledUpdate() async {
    if (!mounted || state.running || ref.read(webDavBusyProvider) || ref.read(resultBusyProvider)) return;
    final logger = ref.read(subLoggerProvider);
    try {
      final cfg = await _cfg();
      if (!mounted || state.running) return;
      if (!cfg.subAutoUpdateEnabled) { stopAutoUpdate(); return; }
      logger.info('自动更新触发（间隔 ${cfg.subAutoUpdateIntervalMin} 分钟）');
      switch (cfg.subAutoUpdateMode) {
        case 'pipeline': await runPipeline();
        case 'landing': await runUpdateAndLanding();
        default: await runSubscription();
      }
    } catch (e) {
      if (mounted) logger.error('自动任务失败：$e');
    }
  }

  /// 停止自动更新定时器。
  void stopAutoUpdate() {
    _autoTimerGeneration++;
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _cancel.cancel();
    stopAutoUpdate();
    _dioSafe.close(force: true);
    _dioInsecure.close(force: true);
    super.dispose();
  }

  /// 单独：订阅IP（转换订阅器 -> addressesapi.txt）。
  Future<void> runSubscription() async {
    if (state.running) return;
    await _runSubscription();
  }

  /// 返回本轮成功落盘的节点；失败、取消或零产出返回 null。
  Future<List<String>?> _runSubscription() async {
    if (!_inPipeline && (ref.read(webDavBusyProvider) || ref.read(resultBusyProvider))) return null;
    if (state.running && !_inPipeline) return null;
    // 流水线调用时由 runPipeline 统一管状态与取消标志。
    if (_inPipeline == false) {
      _begin(RunAction.subscription);
    }
    final logger = ref.read(subLoggerProvider);
    AppConfig? notifyCfg;
    try {
      final cfg = await _cfg();
      _progress('获取订阅');
      if (_cancelRequested) return null;
      notifyCfg = cfg;
      final parser = await ref.read(nodeParserProvider.future);
      if (_cancelRequested) return null;
      logger.info('开始「订阅IP」转换…');
      final result = await _cancel.wait(convertSubscriptions(
        cfg,
        fetch: (url, {label = ''}) {
          if (_cancelRequested) return Future.value('');
          return _safeFetch(url, cfg.subInsecure, cfg, label: label);
        },
        resolve: _resolveHost,
        parser: parser,
        proxy: _systemProxy,
        onLog: (m) => logger.info(m),
        cancel: _cancel,
        onProgress: (done, total) => _progress('获取订阅', done, total),
      ));
      if (_cancelRequested) {
        logger.info('「订阅IP」已取消');
        return null;
      }
      await _trackSourceHealth(cfg,
          okNames: result.okSourceNames,
          failedNames: result.failedSourceNames,
          logger: logger);
      final nodes = result.nodes;
      if (_cancelRequested) {
        logger.info('「订阅IP」已取消');
        return null;
      } else if (nodes.isEmpty) {
        if (result.failedSources > 0) {
          final msg = '「订阅IP」转换失败：全部 ${result.failedSources} 个订阅源均拉取失败或未解析出节点';
          logger.error(msg);
          NotificationHelper.taskFailed(taskName: '订阅IP转换', error: msg);
          _notifyWebhook(cfg, title: '订阅IP转换失败', body: msg, isError: true);
        } else {
          logger.warning('订阅转换无可用节点（请检查 subGenerators/subUrls 配置）');
        }
        return null;
      } else {
        if (result.failedSources > 0) {
          logger.warning('部分订阅源失败：${result.okSources} 个成功，${result.failedSources} 个失败（见上方明细）');
        }
        final outPath = await _resolve(cfg.subOutputFile);
        _progress('保存订阅');
        await writeSubOutput(nodes, outPath);
        await ref.read(resultProvider.notifier).loadFile(outPath);
        logger.success('订阅IP转换完成：${nodes.length} 个节点 -> $outPath');
        _outcome = '获取订阅完成：${nodes.length} 个节点';
        _success = true;
        NotificationHelper.taskComplete(taskName: '订阅IP转换', summary: '${nodes.length} 个节点已保存');
        _notifyWebhook(cfg, title: '订阅IP转换完成', body: '${nodes.length} 个节点已保存 -> $outPath', isError: false);
        return nodes;
      }
    } catch (e) {
      if (_cancelRequested) return null;
      _outcome = '获取订阅失败：$e';
      logger.error(e.toString());
      if (mounted) {
        NotificationHelper.taskFailed(taskName: '订阅IP转换', error: e.toString());
      }
      if (mounted && notifyCfg != null) {
        _notifyWebhook(notifyCfg, title: '订阅IP转换失败', body: e.toString(), isError: true);
      }
      return null;
    } finally {
      if (!_inPipeline) _finish();
    }
  }

  Future<AppConfig> _cfg() async {
    final cfg = state.running ? (_runConfig ??= await readLatestConfig(ref)) : await readLatestConfig(ref);
    ref.read(subLoggerProvider).registerSecrets([
      cfg.githubToken, cfg.webhookUrl, cfg.webdavPassword, cfg.subNodeUuid,
      ...cfg.subUrls,
      for (final generator in cfg.subGenerators)
        if (generator.split('|').length > 2) generator.split('|')[2],
    ]);
    return cfg;
  }

  /// 独立落地检测：对当前结果文件中的每个 IP 做 cdn-cgi/trace，
  /// 用真实 POP 覆盖国家码后写回落地输出文件（默认 `landingOutputFile`）。
  ///
  /// 始终**强制直连**：产品只需要「当前网络的实际落地」（用户 2026-09-29 定稿，
  /// 「代理测落地」与 `landingProxy` 配置已删除）。注意若开着虚拟网卡（TUN），
  /// 流量仍可能被代理客户端接管，此时结果反映的是分流规则决定的出口，
  /// 因此检测开始时会先探测并打印本次连接的实际出口身份（见 [probeEgress]）。
  /// 返回 (成功数, 总数)。
  Future<(int, int)> runLandingCheck() async {
    if (state.running) return (0, 0);
    return _runLandingCheck();
  }

  Future<(int, int)> _runLandingCheck() async {
    if (!_inPipeline && (ref.read(webDavBusyProvider) || ref.read(resultBusyProvider))) return (0, 0);
    if (state.running && !_inPipeline) return (0, 0);
    if (_inPipeline == false) {
      _begin(RunAction.landing);
    }
    final logger = ref.read(subLoggerProvider);
    try {
      final cfg = await _cfg();
      _progress('读取落地检测节点');
      final resultState = ref.read(resultProvider);
      final currentFile = resultState.currentFile;
      final resolvedCurrent = currentFile == null ? null : await _resolve(currentFile);
      String readPath;
      if (resolvedCurrent != null && currentFile!.isNotEmpty && File(resolvedCurrent).existsSync()) {
        readPath = resolvedCurrent;
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
      // 先探明本次连接的实际出口：开着虚拟网卡（TUN）时「直连」仍可能被代理客户端
      // 按规则接管，那测到的就是那个出口的落地。把出口身份打出来，这轮结果才说得清。
      _progress('探测本轮出口');
      final egress = await _cancel.wait(ref.read(egressProbeProvider)(_cancel));
      if (egress == null) {
        logger.warning('出口身份探测失败（cloudflare.com/cdn-cgi/trace 无响应）：本轮落地出口未知');
      } else {
        logger.info('本次出口：${egress.ip} → Cloudflare 判给 '
            '${egress.colo.isEmpty ? '?' : egress.colo}'
            '（若与你宽带实际的公网 IP 不同，说明流量被代理接管）');
      }
      logger.info('开始落地检测（直连，当前网络的实际落地）：${ipOfNode.length} 个独立 IP');
      final landings = <String, String>{};
      final evidenceOf = <String, String>{};
      // IP → 机场码，仅 trace 成功时有值；落地历史需要区分「真实 POP」与「归属地兜底」。
      final airportOf = <String, String>{};
      final traceFailed = <String>[]; // trace 查不到落地的 IP（多为非 CF 直连 IP）
      var done = 0;
      _progress('POP 实测', 0, ipOfNode.length);
      for (final entry in ipOfNode.entries) {
        if (_cancelRequested) {
          logger.info('「落地检测」已取消');
          return (landings.length, ipOfNode.length);
        }
        final landing = await _cancel.wait(ref.read(landingProbeProvider)(entry.key, _cancel));
        done++;
        _progress('POP 实测', done, ipOfNode.length);
        if (landing != null && landing.country.isNotEmpty) {
          landings[entry.key] = landing.country;
          evidenceOf[entry.key] = 'cloudflare_trace';
          airportOf[entry.key] = landing.airport;
          logger.info('  [$done/${ipOfNode.length}] ${entry.key} → ${landing.airport}（${landing.country}）');
        } else if (landing != null) {
          evidenceOf[entry.key] = 'cloudflare_trace_unknown_pop';
          logger.warning('  [$done/${ipOfNode.length}] ${entry.key} → 未知机场码 ${landing.airport}（已保留原标注）');
        } else {
          // 非 CF 边缘 IP 没有 cdn-cgi/trace 接口，先收集起来走归属地兜底。
          traceFailed.add(entry.key);
          evidenceOf[entry.key] = 'trace_unavailable';
          logger.info('  [$done/${ipOfNode.length}] ${entry.key} → trace 未取得 POP（可能非 CF，也可能是网络失败），尝试 IP 归属地估算…');
        }
      }

      // trace 未返回 POP 时只作 IP 归属地估算，不能视作 Cloudflare 实测落地。
      // 先读本地缓存，未命中再批量查询。
      if (traceFailed.isNotEmpty && !_cancelRequested) {
        final cache = await _loadGeoCache();
        final needQuery = <String>[];
        for (final ip in traceFailed) {
          final cached = cache.countries[ip];
          if (cached != null && cached.isNotEmpty) {
            landings[ip] = cached;
            evidenceOf[ip] = 'ip_geo_cache';
          } else {
            needQuery.add(ip);
          }
        }
        if (cache.countries.isNotEmpty) {
          final hit = traceFailed.length - needQuery.length;
          if (hit > 0) logger.info('  归属地缓存命中 $hit 个');
        }
        if (needQuery.isNotEmpty) {
          logger.info('  批量查询 ${needQuery.length} 个 IP 的归属地估算（ip-api.com；结果不是 POP 实测）…');
          _progress('GeoIP 估计', 0, needQuery.length);
          final geo = await _cancel.wait(ref.read(geoProbeProvider)(needQuery, _cancel));
          geo.forEach((ip, cc) {
            landings[ip] = cc;
            evidenceOf[ip] = 'ip_geo_database';
          });
          cache.addAll(geo);
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

      _cancel.check();

      if (landings.isEmpty) {
        _outcome = '落地检测未识别任何 IP，保留原文件';
        _success = false;
        logger.warning('落地检测完成：${ipOfNode.length} 个 IP 均未识别到落地，文件未改动。');
        return (0, ipOfNode.length);
      }
      // 用真实落地覆盖国家码后写回同一文件，并刷新结果页。
      final outPath = await _resolve(cfg.landingOutputFile);
      final outFile = File(outPath);
      await recoverSafeFile(outFile);
      _previousNodes = outFile.existsSync()
          ? (await _readNodes(outPath)).length : 0;
      if (outFile.existsSync()) {
        final oldMeta = await readResultMeta(outFile, await outFile.readAsString());
        final baseline = (oldMeta['push_baseline_node_count'] as num?)?.toInt() ?? 0;
        if (baseline > 0) _previousNodes = baseline;
      }
      final now = DateTime.now().toString().substring(0, 19);
      // 写回前快照：防一次误判的落地覆盖毁掉上一版好结果（保留最近 20 份）。
      final updated = nodes.map((n) => applyRealLanding(n, landings)).toList();
      _progress('保存检测结果');
      await writeSubOutput(updated, outPath, extraMeta: {
        if (egress != null) 'egress_ip': egress.ip,
        if (egress != null && egress.colo.isNotEmpty) 'egress_colo': egress.colo,
        'landing_evidence': evidenceOf,
        'previous_node_count': _previousNodes,
        'push_baseline_node_count': _previousNodes,
      });
      await _appendLandingHistory(now, landings, airportOf, egress);
      // 历史已更新：让结果页的落地历史面板下次读取时重新加载。
      ref.invalidate(landingHistoryProvider);
      await ref.read(resultProvider.notifier).loadFile(outPath);
      // 按国家分组汇总，方便按国家/地区分类使用。
      final groups = <String, int>{};
      for (final n in updated) {
        final cc = nodeCountry(n);
        groups[cc.isEmpty ? '未知' : cc] = (groups[cc.isEmpty ? '未知' : cc] ?? 0) + 1;
      }
      final summary = groups.entries.map((e) => '${e.key}×${e.value}').join('、');
      final measured = evidenceOf.values.where((v) => v == 'cloudflare_trace').length;
      final estimated = evidenceOf.values.where((v) => v.startsWith('ip_geo_')).length;
      _measured = measured;
      _estimated = estimated;
      final unresolved = ipOfNode.length - landings.length;
      _outcome = '落地完成：实测 $measured，估计 $estimated，未确认 $unresolved';
      _success = true;
      logger.success('落地检测完成：${landings.length}/${ipOfNode.length} 个 IP 已更新 '
          '（POP 实测 $measured，归属地估算 $estimated，未识别 $unresolved）→ $outPath（$summary）');
      _notifyWebhook(cfg, title: '落地检测完成', body: '${landings.length}/${ipOfNode.length} 个 IP 已更新（$summary）', isError: false);
      return (landings.length, ipOfNode.length);
    } catch (e) {
      _success = false;
      if (!_cancelRequested) {
        _outcome = '落地检测失败：$e';
        logger.error(_outcome);
      }
      return (0, 0);
    } finally {
      if (!_inPipeline) _finish();
    }
  }

  /// 一键全流程：获取订阅 → 测落地（强制直连）→ 推送 GitHub。
  ///
  /// 两步的出口本就不同（抓取要出得去、测落地要本机真实出口），所以各自钉死：
  /// 抓取走 dio 的系统代理策略，落地检测在 [applyProxyPolicy] 里显式 `DIRECT`，
  /// 用户不必在两步之间开关代理。推送段仅在配了 GitHub 令牌且文件名可推送时执行；
  /// 前两步任一没产出就中止，避免拿空结果去覆盖已有的好文件。
  Future<void> runPipeline() => _runPipeline(push: true);

  Future<void> runUpdateAndLanding() => _runPipeline(push: false);

  Future<void> _runPipeline({required bool push}) async {
    if (state.running || ref.read(webDavBusyProvider) || ref.read(resultBusyProvider)) return;
    _begin(RunAction.pipeline);
    _inPipeline = true;
    final logger = ref.read(subLoggerProvider);
    try {
      final cfg = await _cfg();
      logger.info('━━ 一键全流程：获取订阅 → 测落地 → 推送 ━━');
      final fetchedNodes = await _runSubscription();
      if (_cancelRequested) {
        logger.info('「一键全流程」已取消');
        return;
      }
      if (fetchedNodes == null || fetchedNodes.isEmpty) {
        _success = false;
        _outcome = '全流程中止：本轮订阅无产出';
        logger.error('「一键全流程」中止：订阅转换没有产出节点，落地检测与推送无意义。');
        return;
      }
      final (ok, total) = await _runLandingCheck();
      if (_cancelRequested) {
        logger.info('「一键全流程」已取消');
        return;
      }
      if (total == 0 || ok == 0) {
        _success = false;
        logger.error('「一键全流程」中止：落地检测未识别到任何 IP（$ok/$total），不推送以免覆盖上一版结果。');
        return;
      }
      if (!push) return;
      final issue = pushQualityIssue(nodes: fetchedNodes.length, totalIps: total,
          measured: _measured, estimated: _estimated, previousNodes: _previousNodes,
          minimumNodes: cfg.pushMinimumNodes,
          minimumMeasuredRatio: cfg.pushMinimumMeasuredRatio,
          minimumRetainedRatio: cfg.pushMinimumRetainedRatio);
      if (issue != null) {
        _success = false;
        _outcome = '已保存检测结果，推送被保护规则拦截：$issue';
        logger.warning(_outcome);
        return;
      }
      _progress('推送 GitHub');
      await _pushLandingOutput(cfg, logger);
    } catch (e) {
      _success = false;
      if (!_cancelRequested) {
        _outcome = '全流程失败：$e';
        logger.error(_outcome);
      }
    } finally {
      _inPipeline = false;
      _finish();
    }
  }

  /// 流水线的推送段。
  Future<void> _pushLandingOutput(AppConfig cfg, AppLogger logger) async {
    final file = cfg.landingOutputFile;
    final pusher = _github(cfg);
    if (pusher == null) {
      _outcome += '；未配置 GitHub，跳过推送';
      logger.info('未配置 GitHub 令牌，跳过推送。');
      return;
    }
    if (!GithubPush.isPushable(file)) {
      _success = false;
      _outcome += '；文件名不符合 *_top.txt，未推送';
      logger.warning('输出文件 $file 不符合可推送命名（需 *_top.txt），跳过推送。');
      return;
    }
    try {
      final f = File(await _resolve(file));
      if (!f.existsSync()) {
        logger.error('推送失败：找不到文件 $file');
        return;
      }
      final content = await f.readAsString();
      _cancel.check();
      _pushDispatched = true;
      await pusher.pushFile(file, content, message: 'chore(auto): 更新优选结果');
      try {
        await markResultPushed(f, content);
        await ref.read(resultProvider.notifier).loadFile(f.path);
      } catch (e) {
        logger.warning('推送已成功，本地推送记录保存失败：$e');
      }
      _outcome += '；GitHub 推送成功';
      logger.success('已推送 $file 到 ${cfg.githubRepo}@${cfg.githubBranch}');
      _notifyWebhook(cfg,
          title: '全流程完成', body: '$file 已推送到 ${cfg.githubRepo}', isError: false);
    } catch (e) {
      _success = false;
      _outcome += _cancelRequested ? '；已取消推送' : '；推送失败：$e';
      logger.error('推送失败：$e');
      _notifyWebhook(cfg, title: '全流程推送失败', body: e.toString(), isError: true);
    }
  }

  /// 多出口对照探测：同一批 IP 依次经各配置出口做 cdn-cgi/trace，
  /// 产出对照 CSV 并把结果并入落地历史，用来回答「这个 anycast IP 在不同网络下落到哪」。
  ///
  /// 串行（每个出口内部逐 IP），出口之间也串行 —— 与落地检测同样的限流考虑。
  Future<String?> runEgressComparison() async {
    if (state.running || ref.read(webDavBusyProvider) || ref.read(resultBusyProvider)) return null;
    _begin(RunAction.egressCompare);
    final logger = ref.read(subLoggerProvider);
    try {
      final cfg = await _cfg();
      final profiles = parseEgressProfiles(cfg.probeEgresses);
      if (profiles.isEmpty) {
        logger.warning('未配置任何探测出口（配置页「探测出口」），本次对照未执行。');
        return null;
      }
      final resultState = ref.read(resultProvider);
      final resolvedCurrent = resultState.currentFile == null ? null : await _resolve(resultState.currentFile!);
      final readPath = (resultState.currentFile != null &&
              resultState.currentFile!.isNotEmpty &&
              File(resolvedCurrent!).existsSync())
          ? resolvedCurrent
          : await _resolve(cfg.landingOutputFile);
      final ips = <String>{};
      for (final n in await _readNodes(readPath, logger: logger)) {
        final ep = parseEndpoint(n);
        if (ep != null) ips.add(ep.$1);
      }
      if (ips.isEmpty) {
        logger.warning('没有可对照的 IP（$readPath），请先运行「订阅IP」。');
        return null;
      }
      logger.info('━━ 多出口对照：${profiles.length} 个出口 × ${ips.length} 个 IP（串行）━━');

      final rows = <EgressObservation>[];
      final dir = await getApplicationDocumentsDirectory();
      final historyFile = File('${dir.path}/landing_history.json');
      final now = DateTime.now().toString().substring(0, 19);
      for (final p in profiles) {
        if (_cancelRequested) {
          logger.info('「多出口对照」已取消');
          break;
        }
        final exit = await probeEgress(proxy: p.proxy, cancel: _cancel);
        logger.info('▶ 出口「${p.name}」${p.proxy.isEmpty ? '（直连）' : '（经 ${p.proxy}）'}'
            '：公网侧 ${exit?.ip ?? '未知'}，Cloudflare 判给 ${exit?.colo ?? '?'}');
        final perIp = <String, ({String colo, String cc})>{};
        var done = 0;
        for (final ip in ips) {
          if (_cancelRequested) break;
          final landing = await geolocateCfIp(ip,
                  timeout: const Duration(milliseconds: 4000), proxy: p.proxy.isEmpty ? null : p.proxy,
                  cancel: _cancel);
          done++;
          _progress('多出口对照：${p.name}', done, ips.length);
          final colo = landing?.airport ?? '';
          final cc = landing?.country ?? '';
          perIp[ip] = (colo: colo, cc: cc);
          rows.add((
            ip: ip,
            egress: p.name,
            colo: colo,
            cc: cc,
            exitIp: exit?.ip ?? '',
          ));
          if (done % 100 == 0) logger.info('  [$p.name] 已探测 $done/${ips.length}');
        }
        await recordLandingRound(historyFile, at: now, results: perIp, egressIp: exit?.ip ?? '');
        logger.success('  「${p.name}」完成：识别 ${perIp.values.where((v) => v.cc.isNotEmpty).length}/${ips.length}');
      }

      if (rows.isEmpty) return null;
      _cancel.check();
      final out = File('${dir.path}/landing_compare_${landingStampFor(now)}.csv');
      await safeWriteText(out, renderComparisonCsv(rows));
      ref.invalidate(landingHistoryProvider);

      final pivot = pivotByIp(rows);
      final divergent = countDivergentIps(pivot);
      logger.success('多出口对照完成：${rows.length} 条观测 → ${out.path}（$divergent 个 IP 在不同出口下落地不同）');
      _outcome = '多出口对照完成：${rows.length} 条观测，$divergent 个 IP 不一致';
      _success = true;
      _notifyWebhook(cfg,
          title: '多出口对照完成',
          body: '${profiles.length} 个出口 × ${ips.length} 个 IP，'
              '$divergent 个 IP 落地不一致 → ${out.uri.pathSegments.last}',
          isError: false);
      return out.path;
    } catch (e) {
      logger.error(e.toString());
      return null;
    } finally {
      _finish();
    }
  }

  /// 订阅源健康度：累计每个来源的连续失败轮数，刚好达到阈值时告警一次。
  /// 统计失败绝不影响转换主流程，因此整段吞异常。
  Future<void> _trackSourceHealth(
    AppConfig cfg, {
    required Set<String> okNames,
    required Set<String> failedNames,
    required AppLogger logger,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final before = SourceHealth.fromPrefs(prefs);
      // 同名任务（如多个未打标签的订阅链接都叫 url）只要有一项成功就算成功。
      final all = {...okNames, ...failedNames};
      final failed = failedNames.difference(okNames);
      final after = updateFailureStreaks(before, allSources: all, failed: failed);
      await SourceHealth.saveToPrefs(prefs, after);

      final crossed = sourcesCrossedThreshold(before, after);
      if (crossed.isEmpty) return;
      final detail = crossed.map((n) => '$n（连续 ${after[n]} 轮）').join('、');
      logger.warning('来源连续 $sourceFailureAlertThreshold 轮拉取失败：$detail');
      _notifyWebhook(
        cfg,
        title: '订阅源连续失败',
        body: '以下来源已连续 $sourceFailureAlertThreshold 轮拉取失败：$detail',
        isError: true,
      );
    } catch (_) {
      // 健康度统计不影响主流程
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
  Future<GeoCache> _loadGeoCache() async {
    try {
      final f = await _geoCacheFile();
      await recoverSafeFile(f);
      if (!f.existsSync()) return GeoCache();
      return GeoCache.decode(await f.readAsString());
    } catch (_) {
      // 缓存损坏时忽略，按空缓存处理
    }
    return GeoCache();
  }

  /// 写回 IP → 国家码 归属地缓存。失败静默（不影响主流程）。
  Future<void> _saveGeoCache(GeoCache cache) async {
    try {
      final f = await _geoCacheFile();
      await safeWriteText(f, cache.encode());
    } catch (_) {
      // 写缓存失败不影响落地检测结果
    }
  }

  /// 追加本轮落地观测到 `landing_history.json`（结果页「落地历史」的数据源）。
  /// 失败静默——历史只是辅助信息，不能拖累落地检测本身。
  Future<void> _appendLandingHistory(
    String at,
    Map<String, String> landings,
    Map<String, String> airportOf,
    EgressInfo? egress,
  ) async {
    if (landings.isEmpty) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      await recordLandingRound(
        File('${dir.path}/landing_history.json'),
        at: at,
        results: {
          for (final e in landings.entries)
            e.key: (colo: airportOf[e.key] ?? '', cc: e.value),
        },
        egressIp: egress?.ip ?? '',
      );
    } catch (_) {
      // 忽略历史写入失败
    }
  }

  GithubPush? _github(AppConfig cfg) {
    if (cfg.githubToken.isEmpty) return null;
    final pusher = ref.read(githubPushProvider)(cfg);
    pusher.cancelToken = state.running ? _dioCancel : null;
    return pusher;
  }

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
      final meta = await readResultMeta(File(resolved), content);
      final evidence = meta['landing_evidence'];
      final rows = parseResultLines(content).map((r) {
        final ep = parseEndpoint(r.node);
        return ResultRow(r.node, r.latency,
          evidence is Map && ep != null ? '${evidence[ep.$1] ?? ''}' : '');
      }).toList();
      final issue = ResultState(rows: rows, metadata: meta).qualityIssue(cfg);
      if (issue != null) return (false, 0, '推送保护：$issue');
      logger.info('开始推送 $file 到 GitHub（${cfg.githubRepo}@${cfg.githubBranch}）…');
      final code = await github.pushFile(file, content, message: 'update $file');
      try { await markResultPushed(File(resolved), content); } catch (_) {}
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
    logger.info('$tag→ 请求 ${subscriptionUrlForLog(url)}');
    try {
      final content = await fetchHttpWithRetry(
        dio: dio,
        url: url,
        connectTimeoutSec: cfg.subFetchConnectTimeout,
        sendTimeoutSec: cfg.subFetchTimeout,
        receiveTimeoutSec: cfg.subFetchTimeout,
        maxRetries: cfg.subFetchMaxRetries.clamp(0, 10),
        retryDelayMs: (cfg.subFetchRetryDelay * 1000).round(),
        cancelToken: _dioCancel,
        sleep: _cancel.delay,
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
  return notifier;
});

/// 读取落地历史（文档目录 `landing_history.json`）。缺失或损坏时返回空表。
/// 结果页「落地历史」面板与落地检测共用同一个文件。
Future<LandingHistory> loadLandingHistory() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/landing_history.json');
    if (!f.existsSync()) return {};
    return parseLandingHistory(await f.readAsString());
  } catch (_) {
    return {};
  }
}

/// 落地历史数据源：结果页面板读取它，落地检测写回后使其失效以重新加载。
/// 走 provider 而非让 UI 直接 await 平台通道，测试可注入数据。
final landingHistoryProvider =
    FutureProvider<LandingHistory>((ref) => loadLandingHistory());
