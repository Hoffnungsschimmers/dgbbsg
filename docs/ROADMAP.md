# CFNB 后续发展规划

> **2026-10-06 整理轮**：文档已三合一（`PROJECT_CONTEXT.md`、`HANDOVER.md` 删除，历史章节移入
> `docs/archive/PROJECT_HISTORY.md`，根目录只留 README + PROJECT_OVERVIEW）；根目录旧发布产物与调试日志已清理，
> `.gitignore` 补上 `CFNB-*.zip` 等模式。质量基线更新为 `flutter test` 336/336、`flutter analyze` 0 error / 0 warning / 204 info。
> **分支拓扑未动**（见下方 P0 的「分支归一」，仍需用户确认）。
>
> **2026-10-02 状态**：用户确认的进度/取消、固定配置、推送保护、证据展示、本地恢复、自动任务模式、WebDAV 安全备份与状态、日志、缓存过期、模板说明和 Windows 版本打包已实现。验证记录见 [本轮交接](IMPLEMENTATION_20261002.md)，使用说明见 [README](../README.md)。
>
> 以下是 2026-09-29 的历史规划，保留用于追溯，不代表当前缺陷清单。原文中的分支重置、删除历史文档、代理落地、国家分类与旧测试基线不能直接作为后续执行指令。后续只根据实际使用反馈确定新范围。

> 生成于 2026-09-29，基于代码全面梳理（测试基线 281/281，analyze 0 error / 176 info）。
> 现状事实以 `PROJECT_OVERVIEW.md` 为准；本文只管"接下来做什么"。

## 0. 现状快照（规划的事实依据）

**产品**：三步流水线已完整可用——获取订阅（edgetunnel BEST_SUB + 7 种协议解析 + ip:port 去重）→ 落地检测（cdn-cgi/trace 串行，非 CF IP 已有 ip-api.com 归属地兜底 + 本地缓存 `landing_geo_cache.json`）→ 推送（GitHub *_top.txt / WebDAV 备份 / TG-Discord Webhook）。结果页提供搜索、5 格式导出和行编辑；国家筛选芯片及分组视图已移除。

**质量**：30 个测试文件 281 用例全绿；CI 四 job（analyze/test/Windows/Android）已修复可跑；敏感键走 SecureKV；结果数据文件已正确 gitignore。

**明确的债与缺口**（已逐项用代码核实）：
1. 自动更新定时器只跑「订阅转换」，落地检测与推送不参与 —— 流水线三步仍需手动逐步触发。
2. `LandingProgress`（subscriptions_state.dart）已定义但没有任何 UI 接线 —— 落地检测运行中只有一行"正在检测落地…"文字，无进度。
3. `config_tab.dart` 1322 行、`results_tab.dart` 839 行 —— UI 巨文件，改动风险集中。
4. Android APK 仅由 CI 构建，从未在真机验证；release 签名未配置（用 Flutter 模板默认）。
5. 无 GitHub Releases（CI 产物 30 天过期即丢）、无版本 tag、README.md 已被删除。
6. 文档债：`PROJECT_CONTEXT.md` 过时却仍在库；`HANDOVER.md` 未入库（有意，但与 PROJECT_OVERVIEW 内容重叠老化）。
7. 分支债：本地 `main` 停在旧提交（还带延迟优选计划），`push-clean` 才是实际主线；`feat/subscription-latency-ux`、`refactor/hardening`、`wip/ui-on-main-backup` 三个历史分支无人认领。
8. `gh` CLI 凭据失效，本机无法查 CI 实际红绿。
9. 运行日志是纯内存（`app_logger.dart`），重启即丢，无导出。
10. 归属地兜底依赖 ip-api.com 免费端点：HTTP 明文、45 req/min、batch 每次最多 100 条，无备用源。

## 1. 目标与红线

**北极星**：一键跑完「获取 → 落地检测 → 推送」，可定时全自动，产物可信（落地码真实）。

**红线（勿推翻已定决策）**：
- 不恢复延迟优选（TCP 测速），产品范围就是三步（2026-09-21 用户定稿）。
- 落地检测保持串行，不加并发（防 CF 限流，用户已确认）。
- 注释格式 `IP:端口#国家码 来源名 备注`：国家码必须紧跟 `#` 后第一个 token，备注原样保留 `#`。
- 标签剥离用 `supportedSchemes`，不用 `contains('://')`；删功能要 grep 全仓删干净。
- 每次改动验收线：`flutter test` 全绿 + `flutter analyze` 0 error / lib 零 warning。
- 行为变更先问用户（HANDOVER §6/§7 惯例）。

## 2. P0 —— 卫生清债（半天~1 天，先做，低成本高回报）

| 任务 | 说明 | 验收 |
|---|---|---|
| 分支归一 | 把 `push-clean` 的内容合回/重置到 `main`，此后在 main 开发；删除 `feat/subscription-latency-ux`、`refactor/hardening`、`wip/ui-on-main-backup`（删前确认无独有内容） | `git branch` 只剩 main + 远端同步 |
| 文档三合一 | 删除 `PROJECT_CONTEXT.md`；`HANDOVER.md` 的有效内容（§7 硬教训）并入 `PROJECT_OVERVIEW.md` 后归档；新建 `README.md`（一句话简介 + 截图 + 构建/使用 + 免责） | 新人只读 README + PROJECT_OVERVIEW 即可上手 |
| gh 凭据 | `gh auth login` 恢复后确认 CI 四 job 实际绿 | CI 页全绿，或记录失败原因 |
| 死代码 | `LandingProgress`：要么在 P1 接到 UI，要么按"删干净"规矩先移除（推荐前者，P1 立刻用） | grep 无悬空定义 |
| 工具脚本 | `tool/*.dart` 的 2 条 analyze info（avoid_print 等）清零或加 ignore 注释 | analyze info 全部来自 lib/ 已知项 |

**P0 复核（2026-10-06）**：
- ✅ 文档三合一：`PROJECT_CONTEXT.md` 与 `HANDOVER.md` 已删除，历史内容进 `docs/archive/PROJECT_HISTORY.md`，`README.md` 重建并入库。
- ✅ 死代码：`LandingProgress` 已不存在（取消与阶段进度由 `TaskCancel` + 运行页承担）。
- ⏳ 分支归一：**未执行**，需用户确认（本地 `main` 与 `push-clean` 无共同祖先，删分支不可逆）。
- ⏳ `gh` 凭据：复核仍为「未登录任何主机」，CI 红绿仍无法本机确认。
- ⏳ 工具脚本：`tool/convert_csv.dart` 仍有 `avoid_print` / `unawaited_futures` / `avoid_redundant_argument_values` 数条 info。

## 3. P1 —— 核心链路：全自动流水线（1~2 周，产品价值最大）

### 3.1 一键全流程 `RunAction.pipeline`

- 新增动作「获取 → 落地检测 → 推送」一键执行，复用现有三个动作的实现，逐段日志 + 每段完成/失败各自的 Webhook。
- 落地检测需要用户先决定跑哪种：代理测 / 直连测 / 两次都测（当前使用流程是开代理测一次、关代理测一次）。**这是设计决策，做前问用户**，建议 UI 上做成流水线配置（默认：只跑直连测）。
- 自动更新定时器增加"更新内容"选项：仅获取（现状）/ 全流程。到点自动跑完后可选自动推送。
- 推送段沿用 `isPushable`（仅 `*_top.txt`），推送失败不中断流水线记录，Webhook 报错。

### 3.2 落地检测体验

- 把 `LandingProgress` 接到运行页：进度条（done/total）+ 当前 IP + 预计剩余时间（按已完成均速）。串行保留，只是可视化。
- 失败重试一次（记忆中待确认方案②）：trace 失败的 CF 段 IP 在进入 ip-api 兜底**之前**先重试一次（4s 超时偶发失败主因是 anycast 路由抖动）。改动小、收益直接。
- CF 段预筛（待确认方案①）在 ip-api 兜底落地后**降级为可选加速项**：非 CF IP 现在已有合理答案（归属地=源站所在地），预筛只剩"跳过 trace 直接走缓存/归属地"的提速价值，做不做看 3.2 重试后的实测耗时。

### 3.3 数据可信度

- ip-api 备用源：加一个可配置的备用归属地 API（如 ipwho.is，支持 HTTPS 免费单查），主源失败/限流时降级；同时在配置页明示"非 CF IP 的归属地查询会把该 IP 发给第三方服务"。
- 写回前快照：`runLandingCheck` 覆盖 `landingOutputFile` 前自动备份上一版到 `history/`（带时间戳），支持结果页一键回滚 —— 防"一次错误的落地覆盖毁掉好的结果文件"。
- 运行日志持久化：`app_logger` 增加环形文件日志（文档目录 `logs/`，按天滚动，保留 N 天），运行页加"导出日志"。

### 3.4 代码减债（与 3.1~3.3 同期穿插）

- `config_tab.dart`（1322 行）按区块拆为多文件（订阅/落地检测/GitHub/Webhook/WebDAV/外观各一），行为不变，靠现有 `config_tab_test.dart` 保护。
- `results_tab.dart`（839 行）把表格、筛选芯片、导出抽成独立组件。

**P1 验收**：一键流水线可从点击到 GitHub 推送全程无人值守；落地检测有进度条与重试；`flutter test` ≥ 300 用例全绿。

## 4. P2 —— Android 验证与发布工程（2~4 周，可穿插）

1. **真机验证 Android**：CI 已产 APK，装真机过一遍四 Tab + 返回键 + 落地检测（移动网络下直连测落地是真实使用场景）。修响应式/权限问题（INTERNET 权限确认、文档目录路径）。
2. **正式签名**：生成 release keystore，`android/key.properties`（gitignore）+ `build.gradle.kts` 接 signingConfig。
3. **GitHub Releases 流水线**：打 tag（`v1.1.0`）触发 release workflow —— Windows 便携 zip + MSIX + Android APK 附到 Release；`pubspec.yaml` 版本与 tag 联动。此后每个功能里程碑出一次 Release，替代"30 天过期的 artifact"。
4. **应用内更新检查**（可选）：启动时查 GitHub Releases API 最新版，提示但不强制（自签名 MSIX 无法商店分发，这是唯一升级通道）。

**P2 验收**：Release 页有带三个产物的正式版本；Android 真机完成一次完整流水线。

## 5. P3 —— 产品深化（按需挑选，不排期）

- **订阅源健康度**：记录每源最近成功率/最后成功时间，连续失败的源在结果页置灰提醒（不自动禁用，避免静默丢数据）。
- **结果 diff**：本次获取与上次相比新增/消失哪些 IP，在结果页顶部给一行摘要 —— 订阅源质量的直接信号。
- **推送多目标**：同一 `*_top.txt` 推多个 repo/分支；推送历史（最近 N 次结果 + commit 链接）。
- **headless 模式**：Windows 命令行参数直接跑全流程（`cfnb_app.exe --pipeline`），配合任务计划程序挂机，不弹 UI。核心逻辑已在 core/ 层，可行性高。
- **macOS / Linux 构建验证**：目录都在、从未构建；有需求再投入。
- **i18n**：全中文硬编码，若要英文界面需整体抽字符串 —— 成本高，确有需求再做。

## 6. 风险与依赖

| 风险 | 影响 | 对策 |
|---|---|---|
| ip-api.com 免费额度/明文 HTTP | 归属地兜底批量失败或隐私顾虑 | P1 备用源 + 配置页隐私提示 |
| CF 对 trace 接口限流/变更 | 落地检测核心依赖失效 | 保持串行 + 重试；监控失败率（日志已有汇总） |
| MSIX 自签名证书过期 | 安装包失效 | 发布工程时定证书续期提醒 |
| Android 真机问题未知 | P2 排期可能膨胀 | CI 已出包，先装先测再定范围 |
| 单人维护 | 任何一期中断 | 每期都是独立可停的增量，P0/P1 完成即价值闭环 |

## 7. 建议节奏

1. 本周：P0 全部（半天~1 天）。
2. 下周起：P1 按 3.1 → 3.2 → 3.3 → 3.4 顺序，每小步一提交一验证。
3. P1 收尾后打第一个 tag 出 Release（P2 的 1~3 可提前到此时做）。
4. P3 按实际使用痛点挑，不预先排期。
