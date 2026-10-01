import 'dart:async';
import 'dart:convert';
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
import '../../core/subscription/source_health.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 当前运行的动作类型。
enum RunAction { subscription, landing, pipeline, egressCompare }

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

  /// 正在跑 [runPipeline] 时为 true：单步动作此时不自管 running 状态，
  /// 否则它们会互相把对方的 running 标志清掉。
  bool _inPipeline = false;

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
    if (state.running && !_inPipeline) return;
    // 流水线调用时由 runPipeline 统一管状态与取消标志。
    if (_inPipeline == false) {
      _cancelRequested = false;
      state = state.copyWith(running: true, currentAction: RunAction.subscription);
    }
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
      await _trackSourceHealth(cfg,
          okNames: result.okSourceNames,
          failedNames: result.failedSourceNames,
          logger: logger);
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
      if (!_inPipeline) state = state.copyWith(running: false, clearAction: true);
    }
  }

  Future<AppConfig> _cfg() => readLatestConfig(ref);

  /// 独立落地检测：对当前结果文件中的每个 IP 做 cdn-cgi/trace，
  /// 用真实 POP 覆盖国家码后写回落地输出文件（默认 `landingOutputFile`）。
  ///
  /// 始终**强制直连**：产品只需要「当前网络的实际落地」（用户 2026-09-29 定稿，
  /// 「代理测落地」与 `landingProxy` 配置已删除）。注意若开着虚拟网卡（TUN），
  /// 流量仍可能被代理客户端接管，此时结果反映的是分流规则决定的出口，
  /// 因此检测开始时会先探测并打印本次连接的实际出口身份（见 [probeEgress]）。
  /// 返回 (成功数, 总数)。
  Future<(int, int)> runLandingCheck() async {
    if (state.running && !_inPipeline) return (0, 0);
    if (_inPipeline == false) {
      _cancelRequested = false;
      state = state.copyWith(running: true, currentAction: RunAction.landing);
    }
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
      // 先探明本次连接的实际出口：开着虚拟网卡（TUN）时「直连」仍可能被代理客户端
      // 按规则接管，那测到的就是那个出口的落地。把出口身份打出来，这轮结果才说得清。
      final egress = await probeEgress();
      if (egress == null) {
        logger.warning('出口身份探测失败（cloudflare.com/cdn-cgi/trace 无响应）：本轮落地出口未知');
      } else {
        logger.info('本次出口：${egress.ip} → Cloudflare 判给 '
            '${egress.colo.isEmpty ? '?' : egress.colo}'
            '（若与你宽带实际的公网 IP 不同，说明流量被代理接管）');
      }
      logger.info('开始落地检测（直连，当前网络的实际落地）：${ipOfNode.length} 个独立 IP');
      final landings = <String, String>{};
      // IP → 机场码，仅 trace 成功时有值；落地历史需要区分「真实 POP」与「归属地兜底」。
      final airportOf = <String, String>{};
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
        ).timeout(const Duration(seconds: 12), onTimeout: () => null);
        done++;
        if (landing != null && landing.country.isNotEmpty) {
          landings[entry.key] = landing.country;
          airportOf[entry.key] = landing.airport;
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
          final geo = await geolocateIpCountryBatch(needQuery);
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
      final outFile = File(outPath);
      final now = DateTime.now().toString().substring(0, 19);
      // 写回前快照：防一次误判的落地覆盖毁掉上一版好结果（保留最近 20 份）。
      final snapDir = Directory('${outFile.parent.path}${Platform.pathSeparator}history');
      final snap = snapshotLandingOutput(outFile, snapDir, now);
      if (snap != null) {
        logger.info('已备份上一版结果：${snap.uri.pathSegments.last}（${snapDir.path}）');
      }
      final updated = nodes.map((n) => applyRealLanding(n, landings)).toList();
      await writeSubOutput(updated, outPath, extraMeta: {
        if (egress != null) 'egress_ip': egress.ip,
        if (egress != null && egress.colo.isNotEmpty) 'egress_colo': egress.colo,
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
      logger.success('落地检测完成：${landings.length}/${ipOfNode.length} 个 IP 已更新 → $outPath（$summary）');
      _notifyWebhook(cfg, title: '落地检测完成', body: '${landings.length}/${ipOfNode.length} 个 IP 已更新（$summary）', isError: false);
      return (landings.length, ipOfNode.length);
    } finally {
      if (!_inPipeline) state = state.copyWith(running: false, clearAction: true);
    }
  }

  /// 一键全流程：获取订阅 → 测落地（强制直连）→ 推送 GitHub。
  ///
  /// 两步的出口本就不同（抓取要出得去、测落地要本机真实出口），所以各自钉死：
  /// 抓取走 dio 的系统代理策略，落地检测在 [applyProxyPolicy] 里显式 `DIRECT`，
  /// 用户不必在两步之间开关代理。推送段仅在配了 GitHub 令牌且文件名可推送时执行；
  /// 前两步任一没产出就中止，避免拿空结果去覆盖已有的好文件。
  Future<void> runPipeline() async {
    if (state.running) return;
    _cancelRequested = false;
    _inPipeline = true;
    state = state.copyWith(running: true, currentAction: RunAction.pipeline);
    final logger = ref.read(subLoggerProvider);
    final cfg = await _cfg();
    try {
      logger.info('━━ 一键全流程：获取订阅 → 测落地 → 推送 ━━');
      await runSubscription();
      if (_cancelRequested) {
        logger.info('「一键全流程」已取消');
        return;
      }
      if (ref.read(resultProvider).rows.isEmpty) {
        logger.error('「一键全流程」中止：订阅转换没有产出节点，落地检测与推送无意义。');
        return;
      }
      final (ok, total) = await runLandingCheck();
      if (_cancelRequested) {
        logger.info('「一键全流程」已取消');
        return;
      }
      if (total == 0 || ok == 0) {
        logger.error('「一键全流程」中止：落地检测未识别到任何 IP（$ok/$total），不推送以免覆盖上一版结果。');
        return;
      }
      await _pushLandingOutput(cfg, logger);
    } finally {
      _inPipeline = false;
      state = state.copyWith(running: false, clearAction: true);
    }
  }

  /// 流水线的推送段。
  Future<void> _pushLandingOutput(AppConfig cfg, AppLogger logger) async {
    final file = cfg.landingOutputFile;
    final pusher = _github(cfg);
    if (pusher == null) {
      logger.info('未配置 GitHub 令牌，跳过推送。');
      return;
    }
    if (!GithubPush.isPushable(file)) {
      logger.warning('输出文件 $file 不符合可推送命名（需 *_top.txt），跳过推送。');
      return;
    }
    try {
      final f = File(await _resolve(file));
      if (!f.existsSync()) {
        logger.error('推送失败：找不到文件 $file');
        return;
      }
      await pusher.pushFile(file, await f.readAsString(), message: 'chore(auto): 更新优选结果');
      logger.success('已推送 $file 到 ${cfg.githubRepo}@${cfg.githubBranch}');
      _notifyWebhook(cfg,
          title: '全流程完成', body: '$file 已推送到 ${cfg.githubRepo}', isError: false);
    } catch (e) {
      logger.error('推送失败：$e');
      _notifyWebhook(cfg, title: '全流程推送失败', body: e.toString(), isError: true);
    }
  }

  /// 多出口对照探测：同一批 IP 依次经各配置出口做 cdn-cgi/trace，
  /// 产出对照 CSV 并把结果并入落地历史，用来回答「这个 anycast IP 在不同网络下落到哪」。
  ///
  /// 串行（每个出口内部逐 IP），出口之间也串行 —— 与落地检测同样的限流考虑。
  Future<String?> runEgressComparison() async {
    if (state.running) return null;
    _cancelRequested = false;
    state = state.copyWith(running: true, currentAction: RunAction.egressCompare);
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    try {
      final profiles = parseEgressProfiles(cfg.probeEgresses);
      if (profiles.isEmpty) {
        logger.warning('未配置任何探测出口（配置页「探测出口」），本次对照未执行。');
        return null;
      }
      final resultState = ref.read(resultProvider);
      final readPath = (resultState.currentFile != null &&
              resultState.currentFile!.isNotEmpty &&
              File(resultState.currentFile!).existsSync())
          ? resultState.currentFile!
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
        final exit = await probeEgress(proxy: p.proxy);
        logger.info('▶ 出口「${p.name}」${p.proxy.isEmpty ? '（直连）' : '（经 ${p.proxy}）'}'
            '：公网侧 ${exit?.ip ?? '未知'}，Cloudflare 判给 ${exit?.colo ?? '?'}');
        final perIp = <String, ({String colo, String cc})>{};
        var done = 0;
        for (final ip in ips) {
          if (_cancelRequested) break;
          final landing = await geolocateCfIp(ip,
                  timeout: const Duration(milliseconds: 4000), proxy: p.proxy.isEmpty ? null : p.proxy)
              .timeout(const Duration(seconds: 12), onTimeout: () => null);
          done++;
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
      final out = File('${dir.path}/landing_compare_${landingStampFor(now)}.csv');
      await out.writeAsString(renderComparisonCsv(rows));
      ref.invalidate(landingHistoryProvider);

      final pivot = pivotByIp(rows);
      final divergent = countDivergentIps(pivot);
      logger.success('多出口对照完成：${rows.length} 条观测 → ${out.path}（$divergent 个 IP 在不同出口下落地不同）');
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
      state = state.copyWith(running: false, clearAction: true);
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
