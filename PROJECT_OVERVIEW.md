# CFNB（CF优选工具）项目总览

> 本文档由代码全面梳理生成（2026-09-20），描述项目的功能、架构、数据流、构建方式与当前工作区状态。
> 配套文档：`HANDOVER.md`（2026-09-17 的本地交接笔记，**未入库**，其延迟优选相关内容已过时）、`PROJECT_CONTEXT.md`（**已过时，勿信**）。
> 2026-09-20 更新：按用户确认的产品范围，**延迟优选（TCP 测速排名）已彻底移除**，流程收敛为「获取 → 落地检测 → 推送」（详见 §10）。
> 2026-09-29 更新：① 输出行注释改为 `#国家码 来源名 原始节点备注`（§5.1）；② 修复配置页输入框不回填（§11）；③ CI 的 build_runner 步骤会让 analyze job 必然失败，已删（§12）；④ Windows 构建需 MSVC，本机曾缺工具链（§12）。

## 1. 项目简介

**CFNB** 是一个 Flutter 跨端桌面/移动应用（包名 `cfnb_app`，版本 `1.0.0+1`），核心功能是 **Cloudflare IP 优选**：

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
flutter analyze          # 质量基线：全仓 0 error 0 warning（177 条 info 属正常，CI 用 --no-fatal-infos 容忍）
flutter test             # 基线：265/265 通过（已达成）
flutter build windows --release
# 产物：build/windows/x64/runner/Release/cfnb_app.exe
# 注意：Windows 构建需要 MSVC 工具链（Visual Studio 2022 的「C++ 桌面负载」+ ATL 组件），
#       详见 §12；Dart 代码实际编译进 data/app.so，只改 Dart 时 exe 时间戳不会变。

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
│   ├── system_tray.dart      Windows 托盘菜单（显示窗口/订阅IP/延迟优选/退出）
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
│   │   └── sub_parser.dart          分享链接解析：vless/vmess/trojan/ss/ssr/hy2/tuic
│   │                                 （supportedSchemes 常量在标签剥离逻辑中起关键作用）
│   ├── fetch/node_parser.dart       国家码映射：中文名/三字母码/国旗 emoji → 两位码；
│   │                                splitLabel（标签→国家码+原始备注）、
│   │                                parseTextNodesWithRemark（纯文本列表保留备注）
│   ├── net/
│   │   ├── endpoint.dart            节点行纯解析（`IP:端口#CC 来源 备注`，兼容 IPv6 与旧 `#CC@源`
│   │   │                            格式）：parseEndpoint/nodeCountry/applyRealLanding/
│   │   │                            findCcSourceSep——订阅转换/导出/结果/同步页共用
│   │   ├── ip.dart                  isIp/isIpv4/isIpv6、bracketIpv6Host（IPv6 规范化）、
│   │   │                            isCloudflareIp、geolocateCfIp（落地检测）
│   │   ├── http_fetcher.dart        fetchHttpWithRetry（订阅抓取 + 重试 + 错误分类）
│   │   ├── proxy.dart               readSystemProxy（系统代理读取）
│   │   └── retry.dart               通用重试
│   ├── github/github_push.dart      GitHub Contents API 推送/拉取（pushFile/pullFile/
│   │                                pushMultiple/fetchCommitTime；仅 *_top.txt 可推送）
│   ├── webdav/                      webdav_client.dart（WebDAV 基础客户端）、
│   │                                webdav_sync.dart（配置+结果文件备份/恢复，自动同步）
│   ├── export/result_exporter.dart  结果导出 5 种格式：CSV / Clash YAML / v2ray JSON /
│   │                                sing-box JSON / 纯文本
│   ├── notification/webhook_sender.dart  Telegram / Discord Webhook 通知
│   └── logging/app_logger.dart      内存日志（运行页日志面板数据源）
├── features/
│   ├── subscriptions/
│   │   ├── config_tab.dart          配置页：订阅输入（node/url/both 模式）、抓取参数、
│   │   │                            落地检测（代理）、定时更新、GitHub、Webhook、WebDAV、外观
│   │   ├── run_tab.dart             运行页：获取订阅 / 代理测落地 / 直连测落地
│   │   │                            按钮 + 实时日志
│   │   └── subscriptions_state.dart SubscriptionsNotifier：获取订阅与落地检测两动作的
│   │                                编排与取消、自动更新定时器（5–480 分钟）、Webhook 触发
│   ├── results/                     结果页：表格展示、搜索、编辑、IP 数量统计、
│   │   │                            导出、推送 GitHub、地址选择器
│   │   ├── results_tab.dart / results_table.dart / result_state.dart
│   ├── github_sync/                 同步页：远端 *_top.txt 拉取比对、双向推送、节点增删改
│   ├── webdav/webdav_sync_panel.dart    WebDAV 同步底部面板（AppBar 云图标入口）
│   ├── onboarding/onboarding_wizard.dart  首启 4 步引导（欢迎/输入模式/GitHub/完成）
│   └── widgets/                     通用组件：cards/common/pills/sliders/toast/log_view/
│                                    count_up_text/section_collapsible
└── (数据文件) addressesapi.txt / addressesapi_top.txt  转换与优选输出（工作区根目录）

test/                        28 个测试文件、约 251 个用例（app/core/features 分层）
docs/superpowers/plans/      历史开发计划文档（2026-07 ~ 2026-08）
history/                     结果文件时间戳备份（2026-07-17 的 16 份 ip.txt 快照）
scripts/build_windows.ps1    Windows 发布脚本（MSIX + 便携 zip）
assets/                      country_codes.json（国家码映射数据）、图标、字体
CFYXX-1.0.0-portable.zip     已构建的便携版
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

### 5.2 落地检测（「代理测落地」/「直连测落地」）

`runLandingCheck({required bool useProxy})`（`subscriptions_state.dart`）——延迟优选移除后，本步骤是 `addressesapi_top.txt` 的唯一生产者：

- 读取当前结果文件（优先结果页已加载文件，否则 `landingOutputFile`），对每个**独立 IP**（同 IP 多端口只查一次）调用 `geolocateCfIp`：请求 `http(s)://IP/cdn-cgi/trace`（带 Host 头），解析 `colo=` 机场码 → 国家码。
- `useProxy=true` 时经「落地检测代理」（`AppConfig.landingProxy`，空则系统代理）；`false` 强制直连。
- **串行执行**（防 CF 限流），支持取消；完成后用 `applyRealLanding`（`core/net/endpoint.dart`）覆盖国家码，经 `writeSubOutput` 写入 `landingOutputFile`（txt + `.json` 旁文件，刷新结果页生成时间），日志按 `IP → 机场（国家）` 输出并按国家分组汇总。
- 典型用法：开代理点「代理测落地」→ 关代理点「直连测落地」，对比同一 IP 的两种落地；随后在结果页/同步页把 `*_top.txt` 推送 GitHub。

### 5.3 同步与通知

- **GitHub 推送**：`GithubPush`（Contents API）。仅后缀 `*_top.txt` 的优选结果可推送（`isPushable`）；同步页支持远端拉取/比对/覆盖推送/按行编辑。
- **WebDAV**：手动或自动（定时器在 `main.dart`，间隔 5–480 分钟）备份配置 JSON + 结果文件；可恢复配置与结果。密码经 SecureKV 存储。
- **Webhook**：Telegram（bot token + chat_id URL）/ Discord webhook，任务完成/失败可分别开关，静默失败不影响主流程。

## 6. 配置系统

`AppConfig`（`lib/core/config/app_config.dart`）——普通 Dart 类 + 手写序列化，无 codegen。字段分组：

- **订阅转换**：`subInputMode`（node/url/both）、`subUrls`（支持 `标签|URL` 前缀）、`subGenerators`（`名称|域名|secret`）、`subNodeHost/subNodeUuid`（BEST_SUB 参数）、`subOutputFile`（默认 `addressesapi.txt`）、`subDefaultCountry`、`subResolveDomain`、抓取超时/重试参数、`subInsecure`（跳过 TLS 校验，默认 false）
- **落地检测与输出**：`landingOutputFile`（默认 `addressesapi_top.txt`，落地检测写回 + GitHub/WebDAV 推送目标；旧键 `SUB_LATENCY_OUTPUT_FILE` 读取兜底）、`landingProxy`（落地检测代理，空=系统代理）
- **GitHub**：`githubToken`、`githubRepo`（默认 `Hoffnungsschimmers/mnscn`，fromJson 兜底 `cf-ip`，两者分叉见 §10）、`githubBranch`
- **自动更新**：开关 + 间隔（5–480 分钟），到点自动跑订阅转换
- **Webhook / WebDAV / 外观 / 引导**：见 §5.3 与 `guiTheme`、`hasCompletedOnboarding`

持久化（`ConfigRepository`）：SharedPreferences 存 `app_config_json` + schema 版本；`github_token`/`webhook_url`/`webdav_password` 三个敏感键单独走 SecureKV（系统安全存储），旧明文值启动时一次性迁移。旧版本废弃键（CF DNS/WxPusher/ASN/延迟优选参数等）读取时忽略。

配置页滑块范围（`config_tab.dart`）：连接超时 3–30s、总超时 5–120s、重试 0–5 次 / 0.5–10s、自动更新间隔 10–720 分钟、WebDAV 自动同步间隔 5–480 分钟。

## 7. UI 与交互体系

- **响应式**：Material 3 断点——手机（<600dp）底部 NavigationBar，桌面/平板（≥600dp）左侧 NavigationRail；系统字号缩放限制在 0.85–1.3。
- **4 个 Tab**：配置 / 运行 / 结果 / 同步（GitHub）。Tab 栈用 Stack + Offstage 保活，切换带 fade+slide 动画。
- **桌面特性**：关窗隐藏到系统托盘（`setPreventClose`），托盘菜单可触发订阅IP；window_manager 管窗口（最小 800×600）。
- **快捷键**（`shortcuts.dart`）：Tab 切换/循环、刷新结果、编辑模式、运行订阅、取消运行。
- **首启引导**：4 步向导（欢迎 → 输入模式 → GitHub → 完成），仅弹一次。
- **Android**：返回键非首页 Tab 先回首页、首页双击 2 秒内退出；沉浸式状态栏跟随主题。

## 8. 测试

- 29 个测试文件，**265 个用例全绿**（基线：`flutter test` 265/265；`flutter analyze` 全仓 0 error 0 warning、177 条 info）。覆盖 `core/` 全部模块与主要 feature 状态逻辑（Riverpod ProviderScope 单测，网络/存储均注入 fake）。
- 关键测试语义：订阅转换去重只按 ip:port（`subscription_converter_test.dart`）、**注释保留原始节点备注 + 端到端「获取→写文件→落地检测→结果页解析」不丢备注**（同文件的「输出链路」组）、标签拆分为国家码+备注（`node_parser_test.dart` 的 `splitLabel`/`parseTextNodesWithRemark`）、节点行解析与落地覆盖语义（`endpoint_test.dart`，自 latency_test 迁移）、旧配置键迁移（`app_config_test.dart` 的 `SUB_LATENCY_OUTPUT_FILE` 兜底）、**配置页在配置先解析完成时也要回填**（`config_backfill_test.dart` 第二个用例）、长备注渲染不溢出（`results_table_annotation_test.dart`）。
- 结果行解析保留对旧格式（行尾延迟字符串）的容错：历史生成的文件仍能正确解析出节点/国家码/来源。
- 未跟踪的新测试：`responsive_narrow_test.dart`、`ip_count_box_test.dart`、`config_backfill_test.dart`——均针对工作区新代码编写，在当前工作区全部通过（HANDOVER 曾记录它们在干净 HEAD 上失败，属正常：它们验证的就是未提交的改动）。

## 9. 历史沿革

- 旧版为 Python 脚本（AppConfig 注释可循痕迹：等价于旧版 pydantic `config.Config`），后重写为 Flutter。
- `docs/superpowers/plans/` 保留了 2026-07~08 的开发计划：缺陷修复、订阅与延迟、UI 合并 Android、抓取重试配置、代码加固、首页空白与 GitHub 推送等。
- 最近提交：`e23fdfe` 清理并推送完整项目（WebDAV 同步、IPv6 规范化、配置页重构、GitHub 推送），`bf51f88` 删除 README.md。当前分支 `push-clean` 与 `origin/main` 同步在此提交上。

## 10. ⚠️ 当前工作区状态（截至 2026-09-20）

### 10.1 延迟优选功能已彻底移除（2026-09-20）

梳理当日曾发现工作区处于「延迟优选模块被删一半」的编译不过状态（实现文件已删、调用方与测试仍引用，27 个 error）。当日先恢复对齐基线；随后用户确认产品范围——**「获取、落地地区、推送，就够了」**——据此把延迟优选整个删除：

- 删除 `lib/core/latency/`（prober/filter）与对应测试；纯解析函数统一收敛到 `lib/core/net/endpoint.dart`（此前两处重复，现只此一份）。
- `subscriptions_state.dart`：删 `runLatency`/`runAll`/`RunAction.latency`，落地检测改用 `endpoint.dart` 的 `applyRealLanding`，并把落地输出改写为 `writeSubOutput`（附带 `.json` 旁文件，结果页时间戳保持新鲜）。
- `AppConfig`：删 `subLatencyMaxMs/TopN/Timeout/Workers/Probes/MinSuccessRate`、`subAutoUpdateRunLatency`；`subLatencyOutputFile` 改名 `landingOutputFile`（新键 `LANDING_OUTPUT_FILE`，旧键 `SUB_LATENCY_OUTPUT_FILE` 兜底迁移）。
- UI：运行页延迟按钮、配置页延迟滑块区（改「落地检测」区块）、引导页第 3 步延迟参数、托盘「运行延迟优选」、Ctrl+T 快捷键、导出 CSV 延迟列、编辑弹窗延迟输入框、theme 延迟配色全部移除。
- 保留的容错：`parseResultLines`/`ResultRow.latency` 仍可解析历史文件行尾的延迟字符串（只读兼容，不再是功能）。

验证：`flutter analyze` **0 error**、lib/ 零 warning；`flutter test` **243/243 通过**。

### 10.2 待确认事项（未擅自改）

1. Android APK 本地从未验证构建（环境拉不到 AGP）；CI 修好后由 CI 回答。
2. 远端仓库已迁移：`Hoffnungsschimmers/cfnb` → `Hoffnungsschimmers/dgbbsg`（push 时 GitHub 回显重定向）。本地 `origin` 与本文 §1 仍写旧地址，是否统一待确认。
3. `.mimosa/` 是本地工具目录且未被 `.gitignore` 忽略，是否加忽略待确认。

**已定稿（2026-09-29，用户确认）**：备注原样保留 `#`；提不出国家码的行写占位码 `UN`（原始名只进备注）；`githubRepo` 默认统一为 `Hoffnungsschimmers/mnscn`（构造函数与 `fromJson` 兜底一致，已加回归测试）；落地检测**保持串行**，不加并发。

## 11. 开发约定（硬教训，沿自 HANDOVER §7）

- **标签剥离必须用 `supportedSchemes`**：判断「备注|URL」是否带标签前缀时用 `supportedSchemes.any((s) => url.startsWith(s))`，绝不能用 `contains('://')`——备注本身含 URL 时会被误判。涉及 `config_tab.dart` 与 `subscription_converter.dart`。
- **删功能要删干净**：grep 全仓删残留再复查（历史教训：`maxSpeedMbps` 带宽测速残留；延迟优选移除也按此执行——模块、配置字段、UI、托盘、快捷键、导出列全删，仅保留旧文件读取容错）。
- **`ref.listenManual` 不会补发当前值**：`config_tab.dart` 曾在 `initState` 里用它回填输入框，但主窗口先读过 `configProvider` 时该 provider 已是 data，监听器永不触发 → 配置页所有输入框显示为空（**数据其实完好**，运行时用的也是正确配置）。正解二选一：① `fireImmediately: true`，但此时回调发生在 initState 内，**不能**在其中写 provider（`latestConfigProvider` 的 `??=` 必须 `addPostFrameCallback` 推后，否则 Riverpod 断言「Tried to modify a provider while the widget tree was building」）；② 像 `results_tab.dart` 那样先 `ref.read(configProvider).valueOrNull` 兜一次再监听。判据：用户报「配置丢了」但抓订阅行为正常 → 先查回填，别查存储。
- **注释里国家码必须在 `#` 后第一个 token**：`findCcSourceSep`、结果页 `country`/`source`、`applyRealLanding` 都按这个位置切分，备注只能跟在后面。
- **沟通语言**：简体中文，先结论后细节。
- 提交/改代码前先跑 `flutter test` + `flutter analyze`（全仓零 error/warning）验证。

## 12. CI 与 Windows 构建环境（2026-09-29 实测）

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
