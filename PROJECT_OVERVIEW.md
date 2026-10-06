# CFNB（CF优选工具）项目总览

> 本文是项目的**权威技术总览**：功能、架构、数据流、配置、测试语义、构建环境与硬教训。
> 使用说明见 [`README.md`](README.md)，逐版本变更见 [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md)，
> 逐轮验收记录见 `docs/IMPLEMENTATION_*.md`，后续规划见 [`docs/ROADMAP.md`](docs/ROADMAP.md)。
> 历史沿革与旧工作区快照已移至 [`docs/archive/PROJECT_HISTORY.md`](docs/archive/PROJECT_HISTORY.md)。
>
> **当前状态（2026-10-06 实测）**：版本 `1.1.0+2`；`flutter test` **348/348 全绿**（38 个测试文件）；
> `flutter analyze --no-fatal-infos` **0 error / 0 warning / 204 info**，退出码 0。
> 产品范围为三步：**获取订阅 → 落地检测 → 推送**（延迟优选 TCP 测速已于 2026-09-20 按用户决定彻底移除）。
> 落地检测**只走直连**并记录出口身份；结果页的分类芯片与分组视图已移除，保留搜索、排序、行编辑与整段原始内容编辑。

## 1. 项目简介

**CFNB** 是一个 Flutter 跨端桌面/移动应用（包名 `cfnb_app`，版本 `1.1.0+2`），核心功能是 **Cloudflare IP 优选**：

```
订阅源抓取 → 解析节点 → 去重 → 输出 addressesapi.txt
         → cdn-cgi/trace 落地检测（代理/直连）→ 覆盖国家码 → 输出 addressesapi_top.txt
         → 推送 GitHub / WebDAV 备份 / Webhook 通知
```

- 远端仓库：https://github.com/Hoffnungsschimmers/dgbbsg （原名 `cfnb`，已改名；旧地址靠 GitHub 重定向仍可用）
- 主要目标平台：**Windows**（已验证可构建运行）、**Android**（APK 未验证构建）；工程内也保留了 ios/web/linux/macos 目录。

## 2. 技术栈与环境

| 项 | 值 |
|---|---|
| Flutter / Dart | 3.44.6 stable / 3.12.2（SDK 约束 `^3.12.2`） |
| 状态管理 | flutter_riverpod ^2.5.1（StateNotifier + FutureProvider/StateProvider） |
| 网络 | dio ^5.7.0（双实例：校验 TLS / 跳过证书校验，走系统代理） |
| 持久化 | shared_preferences（配置 JSON）+ flutter_secure_storage（敏感密钥，Windows DPAPI / Android Keystore） |
| 桌面集成 | window_manager、system_tray、local_notifier |
| UI | Material 3、flutter_animate、自定义主题（JetBrainsMono + NotoSansSC 字体） |
| 打包 | msix ^3.18.0（自签名 MSIX：`CFYXX`，identity `cfnb.cfnbapp`） |
| 静态分析 | flutter_lints ^6.0.0 + 严格规则（`analysis_options.yaml`：strict-casts/inference/raw-types） |

## 3. 快速开始

```powershell
flutter pub get
flutter analyze --no-fatal-infos   # 基线：0 error / 0 warning（204 条 info 属正常，CI 同样容忍 info）
flutter test                       # 基线：348/348 通过（2026-10-06 实测）
flutter build windows --release
# 产物：build/windows/x64/runner/Release/cfnb_app.exe
# 注意：Windows 构建需要 MSVC 工具链（Visual Studio 2022 的「C++ 桌面负载」+ ATL 组件），
#       详见 §11；Dart 代码实际编译进 data/app.so，只改 Dart 时 exe 时间戳不会变。

# 便携 zip + 校验文件（版本号取自 pubspec，带时间戳）：
.\scripts\package-windows.ps1
# 打包 MSIX 安装器 + 便携 zip（需管理员 PowerShell）：
.\scripts\build_windows.ps1

# Android（环境曾缺外网拉不到 AGP，未验证）：
flutter build apk --release
```

辅助工具（`tool/`）：`convert_csv.dart`（CSV 转换）、`list_cities.dart`（城市列表，用于国家码映射数据维护）。

## 4. 目录结构

```
lib/
├── main.dart                 入口：窗口初始化、系统托盘、WebDAV 自动同步定时器、
│                             首启引导（Onboarding）、Android 返回键/主题跟随
├── app/
│   ├── app.dart              AppShell：4 Tab（配置/运行/结果/同步），响应式布局
│   │                         （<600dp 底部 NavigationBar；≥600dp NavigationRail），
│   │                         Tab 切换动画（fade+slide），全局快捷键 Actions
│   ├── providers.dart        Riverpod 全局 Provider（config/configRepository/nodeParser/
│   │                         logger/themeMode/editMode/webhookSender/githubPush）
│   ├── theme.dart            Material 3 明暗主题、AppThemeExt 设计令牌扩展
│   ├── breakpoints.dart      响应式断点（compact<600 / medium<840 / expanded≥840）
│   ├── motion.dart           动画时长/曲线常量
│   ├── shortcuts.dart        快捷键定义（切 Tab/刷新/编辑模式/运行/取消）
│   ├── system_tray.dart      Windows 托盘菜单（显示窗口 / 运行订阅IP / 退出）
│   ├── notification_helper.dart  本地系统通知封装
│   └── platform.dart         平台判断
├── core/                     纯逻辑层（不依赖 UI，均被测试覆盖）
│   ├── config/
│   │   ├── app_config.dart          AppConfig：全部配置字段 + 手写 fromJson/toJson/copyWith
│   │   ├── config_repository.dart   SharedPreferences 持久化仓库（schema version=1，
│   │   │                            旧键忽略向后兼容；敏感键迁移至 SecureKV）
│   │   └── secure_kv.dart           安全存储抽象（github_token / webhook_url / webdav_password）
│   ├── subscription/
│   │   ├── subscription_converter.dart  核心流程：收集订阅任务→抓取→解析→去重→输出
│   │   │                                （edgetunnel 协议、sub:// 解码、垃圾节点过滤、
│   │   │                                 按 ip:port 去重、IPv6 方括号化）
│   │   ├── source_health.dart           来源连续失败计数与「达到阈值告警一次」
│   │   │                                 （存独立 prefs 键，不进配置备份）
│   │   └── sub_parser.dart          分享链接解析：vless/vmess/trojan/ss/ssr/hy2/tuic
│   │                                 （supportedSchemes 常量在标签剥离逻辑中起关键作用）
│   ├── fetch/node_parser.dart       国家码映射：中文名/三字母码/国旗 emoji → 两位码；
│   │                                splitLabel（标签→国家码+原始备注）、
│   │                                parseTextNodesWithRemark（纯文本列表保留备注）
│   ├── net/
│   │   ├── endpoint.dart            节点行纯解析（`IP:端口#CC 来源 备注`，兼容 IPv6 与旧 `#CC@源`
│   │   │                            格式）：parseEndpoint/nodeCountry/applyRealLanding/
│   │   │                            findCcSourceSep——订阅转换/导出/结果/同步页共用
│   │   ├── egress_compare.dart      多出口对照：出口清单解析、IP→出口→国家码透视、
│   │   │                            分歧计数与对照 CSV 渲染（纯逻辑）
│   │   ├── ip.dart                  isIp/isIpv4/isIpv6、bracketIpv6Host（IPv6 规范化）、
│   │   │                            isCloudflareIp、geolocateCfIp（落地检测）、
│   │   │                            probeEgress/parseEgressTrace（本次连接出口身份）、
│   │   │                            applyProxyPolicy/proxyPolicyFor（显式钉 DIRECT 的唯一入口）
│   │   ├── geo_cache.dart           GeoIP 归属地缓存（`GeoCache`，`geoCacheLifetime = 7 天`）：
│   │   │                            带时间戳读写，过期项与旧无时间戳项一律重新查询
│   │   ├── push_quality.dart        推送质量门槛纯函数 `pushQualityIssue`：最少节点数、
│   │   │                            POP 实测独立 IP 占比、相对基线的保留占比 → 返回拦截原因
│   │   ├── task_cancel.dart         `TaskCancel` 取消令牌：check/register/delay(可中断退避)/
│   │   │                            cancel + `TaskCancelled` 异常；网络请求关闭与重试等待共用
│   │   ├── landing_history.dart     落地时间线：观测模型、appendLandingRound（去重+
│   │   │                            每 IP 限 8 条）、写回前快照与保留 20 份的裁剪
│   │   ├── http_fetcher.dart        fetchHttpWithRetry（订阅抓取 + 重试 + 错误分类）
│   │   ├── proxy.dart               readSystemProxy（系统代理读取）
│   │   └── retry.dart               通用重试
│   ├── storage/
│   │   ├── safe_file.dart           safeWriteBytes/safeWriteText（临时文件→flush→替换，
│   │   │                            异常保留 .previous）+ recoverSafeFile（中断后恢复）
│   │   └── result_files.dart        writeResultBundle/readResultMeta：结果 txt 与 `.json` 旁文件
│   │                                用内容 SHA-256 关联，按路径串行化写入，写回前落快照
│   ├── github/github_push.dart      GitHub Contents API 推送/拉取（pushFile/pullFile/
│   │                                pushMultiple/fetchCommitTime；仅 *_top.txt 可推送）
│   ├── webdav/                      webdav_client.dart（WebDAV 基础客户端）、
│   │                                webdav_sync.dart（配置+结果文件备份/恢复，自动同步）
│   ├── export/result_exporter.dart  结果导出 5 种格式：CSV / TXT（地址数据）+
│   │                                Clash YAML / v2ray JSON / sing-box JSON（**配置模板**，
│   │                                缺真实协议与认证参数，导出前有说明）
│   ├── notification/webhook_sender.dart  Telegram / Discord Webhook 通知
│   └── logging/app_logger.dart      内存日志环形缓冲（运行页面板数据源）+ 落盘：
│                                    应用目录 `logs/` 按天滚动、保留 7 天、单文件超 1 MB
│                                    轮换一次；入内存/落盘/导出前统一脱敏，落盘失败不影响任务
├── features/
│   ├── subscriptions/
│   │   ├── config_tab.dart          配置页主体：订阅输入（node/url/both 模式）、抓取参数、
│   │   │                            落地检测与多出口探测、定时更新三模式、GitHub（含推送门槛）、
│   │   │                            Webhook、WebDAV、外观
│   │   │   ├── config_entries.dart  条目纯解析：订阅器 `名称|域名|secret`、订阅链接 `备注|URL`
│   │   │   │                        （标签剥离只认 supportedSchemes，见 §10）
│   │   │   ├── config_item_widgets.dart 条目卡片 / 编辑弹窗 / 批量小标签 / 批量粘贴弹窗
│   │   ├── run_tab.dart             运行页：获取订阅 / 测落地（直连 + 出口身份）/ 多出口对照 /
│   │   │                            一键全流程（获取 → 测落地 → 推送）按钮，阶段进度与处理数量、
│   │   │                            运行摘要、停止按钮 + 实时日志（可导出）
│   │   └── subscriptions_state.dart SubscriptionsNotifier：RunAction（fetch/landing/pipeline/
│   │                                egressCompare）编排、固定本轮配置、TaskCancel 取消、
│   │                                并发任务互斥、自动更新定时器（5–480 分钟，三种模式）、
│   │                                Webhook 触发、源健康度告警
│   ├── results/                     结果页：表格展示（含证据来源）、搜索、排序、拖拽调序、
│   │   ├── results_tab.dart / results_table.dart / result_state.dart
│   │   │                            行编辑与整段原始内容编辑、撤销/重做（30 步）、未保存守卫、
│   │   │                            IP 数量统计、导出、推送门槛拦截、落地历史面板、
│   │   │                            快照恢复、地址选择器
│   ├── github_sync/                 同步页：远端 *_top.txt 拉取比对、双向推送、节点增删改
│   ├── webdav/webdav_sync_panel.dart    WebDAV 同步底部面板（AppBar 云图标入口）
│   ├── onboarding/onboarding_wizard.dart  首启 4 步引导（欢迎/输入模式/GitHub/完成）
│   └── widgets/                     通用组件：cards/common/pills/sliders/toast/log_view/
│                                    count_up_text/section_collapsible
└── (数据文件) 结果输出不入库：运行时按 `resolveOutputPath` 写在文档目录
                                （`%USERPROFILE%\Documents\addressesapi.txt` /
                                 `..._top.txt` + 同名 `.json` 旁文件 + 同级 `history/` 快照）

test/                        38 个测试文件、348 个用例（app/core/features 分层；
                             helpers/temp_dir.dart 是用例临时目录清理工具，非用例）
docs/                        RELEASE_NOTES / ROADMAP / IMPLEMENTATION_*（逐轮验收）/
                             archive（历史沿革）/ superpowers（2026-07~08 历史计划与 spec）
scripts/build_windows.ps1    MSIX + 便携 zip 发布脚本（需管理员 PowerShell）
scripts/package-windows.ps1  便携 zip + SHA-256 校验（版本号取自 pubspec，带构建时间戳）
tool/*.dart                  CSV 转换、城市列表（国家码映射数据维护）
assets/                      country_codes.json（国家码映射数据）、图标、字体
```

## 5. 核心数据流

### 5.1 订阅转换（「订阅IP」）

入口 `convertSubscriptions`（`lib/core/subscription/subscription_converter.dart`），编排逻辑在 `SubscriptionsNotifier.runSubscription`：

1. **收集任务** `collectSubscriptionTasks`：按 `subInputMode`（node/url/both）组装 `[(来源名, [候选URL...]), ...]`。
2. **订阅器协议（edgetunnel）**：请求带特征 UA `v2rayN/edgetunnel (…cmliu/edgetunnel)` 触发 BEST_SUB 模式；候选 URL 依次为 `/sub?token=…`（有 secret 时，token = `md5(md5(host+uuid))`）→ `/sub?host=&uuid=` → `/sub?token=auto`，`fetchFirstWorking` 找到首个可解析出节点的即停。
3. **解码与解析**：`sub://` 分享链接先解码；base64 订阅解码；`SubParser.parseSubscriptionLinks` 解析 7 种协议链接；失败回退按纯 IP/域名文本解析（兼容 bestcf 类 txt 列表）。
4. **过滤与去重**：垃圾节点过滤（超长子域名 + 推广关键词）；**只按 `ip:port` 去重**（同 IP+端口仅保留首次出现，不同端口视为不同节点）；域名可选 DNS 解析（`subResolveDomain`）。
5. **输出** `writeSubOutput`：`addressesapi.txt`（LF 换行）+ `.json` 旁文件（`generated_at`/`node_count`）。

节点行格式：`IP:端口#国家码 来源名 原始节点备注`，如 `172.64.145.93:443#SG 麒麟优选 🇸 新加坡 01`。
规则（2026-09-29 定稿）：国家码取自原始名并**必须紧跟在 `#` 后**（`findCcSourceSep` 与结果页都按「# 后第一个空格」切分，位置不能挪）；
原始名剥掉国家码后剩下的原文作备注跟在来源名之后；备注**原样保留 `#`**（只有行首第一个 `#` 是结构性的），仅压缩换行与连续空格（`_cleanRemark`）；
原始名开头/结尾正好等于来源名时不重复拼接（`_stripSourceDup`）；纯文本列表源（bestcf 类 txt）同样保留 `#CC` 后的原文；
提不出国家码且未配默认国家码时写占位码 `UN`（`unknownCountryTag`），原始名只出现在备注里，落地检测会用真实落地码覆盖；
同 ip:port 去重仍只保留首次出现那条（含其来源名与备注）；IPv6 自动方括号包裹（`bracketIpv6Host`）；兼容旧 `#CC@来源` 格式读取。

### 5.2 落地检测（只有「测落地」，强制直连）

`runLandingCheck()`（`subscriptions_state.dart`）——延迟优选移除后，本步骤是 `addressesapi_top.txt` 的唯一生产者：

- 读取当前结果文件（优先结果页已加载文件，否则 `landingOutputFile`），对每个**独立 IP**（同 IP 多端口只查一次）调用 `geolocateCfIp`：请求 `http(s)://IP/cdn-cgi/trace`（带 Host 头），解析 `colo=` 机场码 → 国家码。
- **始终直连**：「代理测落地」按钮与 `AppConfig.landingProxy` 已删除（2026-09-29 用户定稿：只需要当前网络的实际落地）。旧键 `LANDING_PROXY` 读取时忽略、也不会再写回（有回归测试）。
- **出口身份探针**：检测前先请求 `https://www.cloudflare.com/cdn-cgi/trace`（`probeEgress` / `parseEgressTrace`，`core/net/ip.dart`），日志打印「本次出口 `<ip>` → Cloudflare 判给 `<colo>`」，并把 `egress_ip` / `egress_colo` 写进 `*_top.txt.json` 旁文件。动机：开着虚拟网卡（TUN）时「直连」并不等于本机宽带出口 —— 流量是否被代理接管取决于客户端对该 IP 的分流规则，App 层无法可靠绕过（绑源地址改变不了 Windows 的路由选择，anycast 的 colo 又由 BGP 决定）。给出出口身份，多轮测量的结果才可归属、可对比。探测失败只记 warning，不影响检测。
- **写回前快照 + 落地时间线**：覆盖 `landingOutputFile` 前先把上一版复制到同目录 `history/landing_<时间戳>.txt`（保留最近 20 份，`landingSnapshotKeep`），防一次误判的落地覆盖毁掉好结果；同时把本轮观测追加进文档目录 `landing_history.json`（IP → 最多 8 条 `{at, colo, cc, egress_ip}`，与上一条完全相同则不追加，避免自动更新灌满重复项）。结果页「落地历史」按钮（`landingHistoryProvider` + `_LandingHistoryDialog`）按 IP 展开查看历次落地与当时的出口身份 —— 这正是「同一 anycast IP 在不同网络下落点不同」的对照记录。落地检测写回后会 `ref.invalidate(landingHistoryProvider)` 让面板重新加载。
- **多出口对照探测** `runEgressComparison()`：配置页「探测出口」里每行一条 `名称|host:port`（`|` 后留空即直连，默认只有一条 `本机直连|`），运行页「多出口对照」让**同一批 IP 依次经各出口**做 cdn-cgi/trace，产出 `Documents/landing_compare_<时间戳>.csv`（`ip,egress,colo,country,exit_ip`），并按出口逐个并入落地历史（`recordLandingRound` 先读后追加，不会覆盖既有历史）；日志末尾给出「多少个 IP 在不同出口下落地不同」。这是「同一个 anycast IP 在不同网络下落点不同」的直接验证手段，不必人工开关代理反复测。纯逻辑在 `core/net/egress_compare.dart`（`parseEgressProfiles` / `pivotByIp` / `countDivergentIps` / `renderComparisonCsv`）。

- **一键全流程** `runPipeline()`：获取订阅 → 测落地 → 推送 GitHub，三步串成一次点击。关键点是**两步的出口本就不同且互不冲突**：抓取走 dio 的系统代理策略，落地检测经 `applyProxyPolicy` 显式钉 `DIRECT`，所以用户不需要在中间开关代理（TUN 是否接管由出口探针当场揭示）。任一前置步骤没产出即中止：转换 0 节点就不测落地，落地 0 识别就不推送，避免拿空结果覆盖上一版好文件。推送段仅在配了 GitHub 令牌且文件名符合 `*_top.txt` 时执行，失败走 Webhook 告警。
- **串行执行**（防 CF 限流），支持取消；完成后用 `applyRealLanding`（`core/net/endpoint.dart`）覆盖国家码，经 `writeSubOutput` 写入 `landingOutputFile`（txt + `.json` 旁文件，刷新结果页生成时间），日志按 `IP → 机场（国家）` 输出并按国家分组汇总。

### 5.3 同步与通知

- **GitHub 推送**：`GithubPush`（Contents API）。仅后缀 `*_top.txt` 的优选结果可推送（`isPushable`）；同步页支持远端拉取/比对/覆盖推送/按行编辑。
- **WebDAV**：手动或自动（定时器在 `main.dart`，间隔 5–480 分钟）备份配置 JSON + 结果文件；可恢复配置与结果。密码经 SecureKV 存储。
- **Webhook**：Telegram（bot token + chat_id URL）/ Discord webhook，任务完成/失败可分别开关，静默失败不影响主流程。
- **订阅源健康度告警**（2026-09-29）：`core/subscription/source_health.dart` 跨轮次累计每个来源的连续失败次数，**刚好达到阈值（`sourceFailureAlertThreshold = 3`）那一轮**通过 Webhook 告警一次，之后继续失败不再重复轰炸；来源恢复成功即清零。计数存在 SharedPreferences 的独立键 `source_health_json`，**刻意不进 `AppConfig`**——它是运行时状态，不该跟着配置导出，也不该被 WebDAV 恢复配置时覆盖回旧值。同名任务（多个未打标签的订阅链接都叫 `url`）只要有一项成功就不算失败。

## 6. 配置系统

`AppConfig`（`lib/core/config/app_config.dart`）——普通 Dart 类 + 手写序列化，无 codegen。字段分组：

- **订阅转换**：`subInputMode`（node/url/both）、`subUrls`（支持 `标签|URL` 前缀）、`subGenerators`（`名称|域名|secret`）、`subNodeHost/subNodeUuid`（BEST_SUB 参数）、`subOutputFile`（默认 `addressesapi.txt`）、`subDefaultCountry`、`subResolveDomain`、抓取超时/重试参数、`subInsecure`（跳过 TLS 校验，默认 false）
- **落地检测与输出**：`landingOutputFile`（默认 `addressesapi_top.txt`，落地检测写回 + GitHub/WebDAV 推送目标；旧键 `SUB_LATENCY_OUTPUT_FILE` 读取兜底）。落地检测**无代理参数**：`landingProxy` 已删除，旧键 `LANDING_PROXY` 读取时忽略；`probeEgresses`（多出口对照的出口清单，默认 `['本机直连|']`）
- **GitHub**：`githubToken`、`githubRepo`（构造函数与 `fromJson` 兜底**都是** `Hoffnungsschimmers/mnscn`，已加回归测试防分叉）、`githubBranch`
- **推送质量门槛**（手动与自动共用，配置页 GitHub 区块可调）：`pushMinimumNodes`（默认 1）、`pushMinimumMeasuredRatio`（默认 0.5，独立 IP 中 POP 实测的占比，GeoIP 估计不计入）、`pushMinimumRetainedRatio`（默认 0.5，相对上次成功推送基线的保留占比）。被拦截的结果仍留在本地，重复运行**不会**重置基线；只有成功推送才更新基线。
- **自动更新**：`subAutoUpdateEnabled` + `subAutoUpdateIntervalMin`（配置页滑块 10–720 分钟，定时器按 `clamp(5, 720)` 兜底）+ `subAutoUpdateMode`（`subscription`｜`landing`｜`pipeline`，默认仅获取，避免升级后自动推送）。仅在软件运行期间生效（关到托盘仍跑），已有任务时跳过不排队，任务运行/同步/手动推送恢复互斥。
- **Webhook / WebDAV / 外观 / 引导**：见 §5.3 与 `guiTheme`、`hasCompletedOnboarding`

持久化（`ConfigRepository`）：SharedPreferences 存 `app_config_json` + schema 版本；`github_token`/`webhook_url`/`webdav_password` 三个敏感键单独走 SecureKV（系统安全存储），旧明文值启动时一次性迁移。旧版本废弃键（CF DNS/WxPusher/ASN/延迟优选参数等）读取时忽略。配置解析失败时**保留原始损坏文件备份**并用默认配置启动；保存经队列串行化，失败提示。

配置页滑块范围（`config_tab.dart`）：连接超时 3–30s、总超时 5–120s、重试 0–5 次 / 0.5–10s、自动更新间隔 10–720 分钟、WebDAV 自动同步间隔 5–480 分钟。

## 7. UI 与交互体系

- **响应式**：Material 3 断点——手机（<600dp）底部 NavigationBar，桌面/平板（≥600dp）左侧 NavigationRail；系统字号缩放限制在 0.85–1.3。
- **4 个 Tab**：配置 / 运行 / 结果 / 同步（GitHub）。Tab 栈用 Stack + Offstage 保活，切换带 fade+slide 动画。
- **结果页分类已移除**：国家筛选芯片和按国家分组视图已删除（连同其测试 `results_filter_chips_test.dart`）。
- **结果页编辑体系（2026-10-03）**：行编辑弹窗拆 `地址:端口` 与 `来源 备注` 两栏；另有「原始内容」可编辑视图，切回解析视图时 `applyRawText` **逐行**校验，任一行不是 `地址:端口` 就抛「第 N 行不是有效的地址:端口」并**整批拒绝**（不做部分应用）。只有与原节点**完全一致**的行保留实测证据，改过地址或注记的行证据清空、需重测。撤销/重做栈上限 30 步；`dirty` 未保存时切文件/重载会弹「继续编辑/丢弃」确认；保存走按路径串行的写队列。快照列表只列出 `snapshot_target` 等于当前文件的记录，恢复前先备份现文件。
- **桌面特性**：关窗隐藏到系统托盘（`setPreventClose`），托盘菜单可触发订阅IP；window_manager 管窗口（最小 800×600）。
- **快捷键**（`shortcuts.dart`）：Tab 切换/循环、刷新结果、编辑模式、运行订阅、取消运行。
- **首启引导**：4 步向导（欢迎 → 输入模式 → GitHub → 完成），仅弹一次。
- **Android**：返回键非首页 Tab 先回首页、首页双击 2 秒内退出；沉浸式状态栏跟随主题。

## 8. 测试

- 38 个测试文件，**348 个用例全绿**（基线：`flutter test` 348/348；`flutter analyze --no-fatal-infos` 0 error / 0 warning、204 条 info；均为 2026-10-06 实测）。覆盖 `core/` 全部模块与主要 feature 状态逻辑（Riverpod ProviderScope 单测，网络/存储均注入 fake）。
- 关键测试语义：订阅转换去重只按 ip:port（`subscription_converter_test.dart`）、**注释保留原始节点备注 + 端到端「获取→写文件→落地检测→结果页解析」不丢备注**（同文件的「输出链路」组）、标签拆分为国家码+备注（`node_parser_test.dart` 的 `splitLabel`/`parseTextNodesWithRemark`）、节点行解析与落地覆盖语义（`endpoint_test.dart`，自 latency_test 迁移）、旧配置键迁移（`app_config_test.dart` 的 `SUB_LATENCY_OUTPUT_FILE` 兜底，以及 `githubRepo` 缺键兜底必须等于构造函数默认）、**配置页在配置先解析完成时也要回填**（`config_backfill_test.dart` 第二个用例）、长备注渲染不溢出（`results_table_annotation_test.dart`）、**标签剥离规则本身有直测**（`config_entries_test.dart`：备注自身含 `://`、`|` 之后为空、节点链接不拼备注、拆拼往返不变形）。
- 可靠性与数据安全：`core/reliability_test.dart`（写临时文件-替换-恢复、内容哈希与旁文件错配拒绝、GeoIP 过期、脱敏）、`features/subscriptions/pipeline_reliability_test.dart`（固定本轮配置、检测中取消、动作互斥、数量骤减拦截、0 节点不写回）、`features/subscriptions/pipeline_test.dart`（一键全流程编排，须用 `SharedPreferences.setMockInitialValues` 种配置，见 §10）、`features/results/result_editing_test.dart`（行编辑/整段原始文本校验/撤销重做/未保存守卫/串行保存）。
- 结果行解析保留对旧格式（行尾延迟字符串）的容错：历史生成的文件仍能正确解析出节点/国家码/来源。延迟片段**只认行尾形态**（`50.00 ms` / `56.00ms`），行中出现而后面还有文字的当作备注原文，避免整段被吞。
- 测试全部入库；新增/删除用例后须同步本文数字与 `docs/RELEASE_NOTES.md`。国家筛选相关的 `results_filter_chips_test.dart` 已随功能删除，不要按旧文档重建。

## 9. 当前状态与遗留事项（2026-10-06）

历史沿革、延迟优选移除过程（2026-09-20）与旧工作区快照已移至
[`docs/archive/PROJECT_HISTORY.md`](docs/archive/PROJECT_HISTORY.md)，本文只描述当前代码。

**版本线**：`1.1.0+2`（`pubspec.yaml`、`lib/app/version.dart`、`msix_config.msix_version` 三处需同步）。
远端 `origin` 已是 `Hoffnungsschimmers/dgbbsg`。`push-clean` 与 `origin/main` 同点。

**遗留事项**（逐项核实过现状）：

1. Android 只有 CI 构建，从未真机验收；release 签名未配置，APK 走 debug key。
2. 无 GitHub Releases、无版本 tag，CI 产物 30 天过期即丢；本机 `gh` 未登录，无法直接查 CI 红绿。
3. 分支拓扑待归一：本地 `main`（`8723274`）与 `push-clean` **无共同祖先**（不同血脉），另有
   `refactor/hardening`、`feat/subscription-latency-ux`、`wip/ui-on-main-backup` 三个陈旧分支。
   删分支/重置 main 属高危且不可逆，**未获得用户确认前不动**。
4. 巨文件：`results_tab.dart` 1309 行、`config_tab.dart` 1069 行（2026-10-06 已拆出 `config_entries.dart` 纯解析与 `config_item_widgets.dart` 条目控件；剩余区块与 `_save`/控制器回填强耦合，硬拆会碰 §10 的 `ref.listenManual` 坑）、`subscriptions_state.dart` 964 行。
5. 配置页与订阅转换各有一份「备注|URL」标签剥离实现（`config_entries.dart` 与 `subscription_converter.fetchSingle`），规则相同但代码未合并——合并会动到抓取主路径，需单独一轮带测试的改动。
6. 非 CF IP 的归属地兜底仍是**单源** `http://ip-api.com/batch`（明文 HTTP、45 req/min、每次最多 100 条），无备用源；缓存 7 天过期（`geo_cache.dart`）。

**已完成（2026-10-06）**：根目录历史发布产物（旧 `CFYXX-*` 包）、调试日志与 7 月的结果样本文件已清理；
`.gitignore` 补上 `CFNB-*.zip` / `*-windows-portable*.zip` / `*.zip.sha256`，堵住 `git add -A` 误提二进制；
`build/`、`dist/`、`.dart_tool/` 保留在本地不入库。

**已定稿（不要再议）**：产品范围三步、不做延迟优选；落地检测保持**串行**、只走**直连**（不加并发、不留代理参数）；备注原样保留 `#`；提不出国家码写占位码 `UN`；`githubRepo` 两处默认一致；国家分类芯片与分组视图已删除，不要按旧文档重建。

## 10. 开发约定（硬教训）

- **标签剥离必须用 `supportedSchemes`**：判断「备注|URL」是否带标签前缀时用 `supportedSchemes.any((s) => url.startsWith(s))`，绝不能用 `contains('://')`——备注本身含 URL 时会被误判。涉及 `features/subscriptions/config_entries.dart`（2026-10-06 从 config_tab 抽出，已有 `config_entries_test.dart` 直测）与 `core/subscription/subscription_converter.dart` 的 `fetchSingle`。
- **删功能要删干净**：grep 全仓删残留再复查（历史教训：`maxSpeedMbps` 带宽测速残留；延迟优选移除也按此执行——模块、配置字段、UI、托盘、快捷键、导出列全删，仅保留旧文件读取容错）。
- **`ref.listenManual` 不会补发当前值**：`config_tab.dart` 曾在 `initState` 里用它回填输入框，但主窗口先读过 `configProvider` 时该 provider 已是 data，监听器永不触发 → 配置页所有输入框显示为空（**数据其实完好**，运行时用的也是正确配置）。正解二选一：① `fireImmediately: true`，但此时回调发生在 initState 内，**不能**在其中写 provider（`latestConfigProvider` 的 `??=` 必须 `addPostFrameCallback` 推后，否则 Riverpod 断言「Tried to modify a provider while the widget tree was building」）；② 像 `results_tab.dart` 那样先 `ref.read(configProvider).valueOrNull` 兜一次再监听。判据：用户报「配置丢了」但抓订阅行为正常 → 先查回填，别查存储。
- **注释里国家码必须在 `#` 后第一个 token**：`findCcSourceSep`、结果页 `country`/`source`、`applyRealLanding` 都按这个位置切分，备注只能跟在后面。
- **「不设 proxy」不等于直连**：Dart `HttpClient` 的默认 `findProxy` 是 `findProxyFromEnvironment`，会读 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。任何需要真直连的路径（落地检测、出口探测、归属地兜底）必须显式钉 `DIRECT`，统一走 `core/net/ip.dart` 的 `applyProxyPolicy` / `proxyPolicyFor`。GitHub API 推送本来就是这么做的。
- **测 notifier 编排要种 prefs，只 override `configProvider` 没用**：`_cfg()` 走 `readLatestConfig` → 优先 `latestConfigProvider`，否则 `repo.current`。空 SharedPreferences 会回落到**默认配置（`both` + 内置 10 个订阅器）**，于是测试真的去发请求（测试绑定一律返回 400 → 触发退避重试 → 用例超时 30s）。正解是 `SharedPreferences.setMockInitialValues({'flutter.app_config_json': ...})` 把目标配置种进去，见 `pipeline_test.dart`。
- **`testWidgets` 里不要直接 await 含异步依赖的链**：fake async 区里定时器要靠 `pump` 才走；纯逻辑编排用例用普通 `test()` + `ProviderContainer` 更省事（也避开 widget 绑定对 HttpClient 的拦截语义）。
- **仓库正文是 LF，脚本改文件必须用二进制模式**：`core.autocrlf=false` 且没有 `.gitattributes`，git 不做行尾转换。用 Python 文本模式 `open(path,'w')` 重写会把文件整份换成 CRLF，一次提交能产生 4047 增 / 4047 删的整文件 diff，把真实改动全埋掉。判据：`git diff --ignore-cr-at-eol --stat` 输出为空 → 纯行尾噪音。改文件优先用编辑工具，必须脚本化时走 `open(path,'wb')`。
- **行尾噪音两个方向都要查**：漏网的不止 CRLF 写回，还有整仓里唯一存成 `i/crlf` 的文件被工具顺手降为 LF——同样表现为整文件 diff（2026-10-06 的 `subscription_converter_test.dart`，`c417a28` 统一行尾时漏掉它）。判据是 `git ls-files --eol`（列 1 是 index、列 2 是工作区），别只看 `git diff --stat`。
- **批量改文件不要用拼出来的 sed/awk**：本轮用变量转义锚点的 `sed -i` 批量插 import，正则被转义搞坏成「匹配几乎所有行」，把 import 插进了类体；`git restore` 回到刚提交的 HEAD 再逐个用编辑工具改，代价更低。规则：改完立刻 `git diff --numstat` 核对行数是否符合预期（改 5 个文件应是十几行，出现 344/343 就是坏了）。
- **Windows 全量跑会偶发临时目录删除失败，别当成用例回归**：tearDown 里 `dir.delete(recursive: true)` 撞上杀软/索引仍持有的句柄会抛 `PathAccessException errno=32`，并行全量跑偶发红一条、单跑恒过。清理临时目录不是被测行为，`test/helpers/temp_dir.dart` 的 `removeTempDir` 重试 10 次后放弃。**只在普通 `test()` 用**：`testWidgets` 的 fake async 区里 `Future.delayed` 要靠 `pump` 才走，加进去直接超时。
- **沟通语言**：简体中文，先结论后细节。
- 提交/改代码前先跑 `flutter test` + `flutter analyze`（全仓零 error/warning）验证。

## 11. CI 与 Windows 构建环境（2026-09-29 实测）

### CI（`.github/workflows/ci.yml`）

analyze（`--no-fatal-infos`）+ test + Windows 便携包 + Android APK。原先有个「`dart run build_runner build` 检查代码生成是否最新」的步骤，但本项目**没有任何 codegen**（`AppConfig` 是手写序列化）且 `build_runner` 不在依赖里 → 该步骤必然失败 → analyze job 红 → `needs: [analyze, test]` 的两个构建 job 从不执行。已删除。仓库里残留的 3 个 `test/` warning（`must_call_super`、两处 `asFuture` 缺泛型）在 `--no-fatal-infos` 下仍然致命，也已清零。

### 本机 Windows 构建的四个坑

1. **缺 MSVC**：`flutter doctor` 报「Visual Studio not installed」时无法构建桌面端；`D:\env\MinGW` 之类不能用。装 Visual Studio 2022 Build Tools + 「使用 C++ 的桌面开发」负载（本机装在 `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`）。
2. **`flutter_secure_storage` 需要 ATL**：报 `无法打开包括文件: atlstr.h`，ATL 不在 VCTools 的 `--includeRecommended` 内，要显式加组件 `Microsoft.VisualStudio.Component.VC.ATL`。winget 对已安装的 Build Tools 会走「查升级」分支并**忽略 `--override`**，必须加 `--force` 才会带参数重跑 bootstrapper；`setup.exe modify --installPath ...` 在本机直接返回 87（参数被拒）。
3. **换过 VS 大版本要清 CMake 缓存**：`build/windows/x64/CMakeCache.txt` 里记着旧生成器（如 `Visual Studio 18 2026`），新工具链会报 `CMake Error: generator ... Does not match the generator used previously`。只删 `CMakeCache.txt` 和 `CMakeFiles/` 即可，不必 `rm -rf build`。
4. **LNK1104 打不开 exe**：说明有实例在跑（关窗只是隐藏到系统托盘），先 `Stop-Process -Name cfnb_app -Force` 再构建。另外只改 Dart 时 exe 时间戳不会变——Dart 代码编译进 `data/app.so`。

### 用户数据落盘位置

- 配置：`%APPDATA%\com.cfnb\cfnb_app\shared_preferences.json`（键 `flutter.app_config_json`）+ 同目录 `flutter_secure_storage.dat`（`github_token` / `webhook_url` / `webdav_password`）。
- 结果文件：`resolveOutputPath` 以 `getApplicationDocumentsDirectory()` 为基目录，即 `%USERPROFILE%\Documents\addressesapi.txt`（另有同名 `.json` 旁文件记录生成时间与节点数）。
