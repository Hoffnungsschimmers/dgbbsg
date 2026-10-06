# 历史沿革与旧工作区快照（归档）

> 本文件是 [`../../PROJECT_OVERVIEW.md`](../../PROJECT_OVERVIEW.md) 瘦身时移出的历史章节，**只用于追溯**。
> 当前事实一律以 PROJECT_OVERVIEW 与 README 为准；本文提到的功能大多已删除。
> 归档时间：2026-10-06。

## 1. 项目来历

- 旧版为 Python 脚本（`AppConfig` 注释仍留有痕迹：等价于旧版 pydantic `config.Config`），后整体重写为 Flutter。
- `docs/superpowers/` 保留了 2026-07 ~ 2026-08 的开发计划与 spec：缺陷修复、应用优化、订阅与延迟、UI 合并 Android、抓取重试配置、代码加固、首页空白与 GitHub 推送。这些计划里的「延迟测试/带宽测速」方向已在 2026-09 被否决。

## 2. 延迟优选功能彻底移除（2026-09-20）

梳理当日曾发现工作区处于「延迟优选模块被删一半」的编译不过状态（实现文件已删、调用方与测试仍引用，27 个 error）。当日先恢复对齐基线；随后用户确认产品范围——**「获取、落地地区、推送，就够了」**——据此把延迟优选整个删除：

- 删除 `lib/core/latency/`（prober/filter）与对应测试；纯解析函数统一收敛到 `lib/core/net/endpoint.dart`（此前两处重复，现只此一份）。
- `subscriptions_state.dart`：删 `runLatency`/`runAll`/`RunAction.latency`，落地检测改用 `endpoint.dart` 的 `applyRealLanding`，并把落地输出改写为 `writeSubOutput`（附带 `.json` 旁文件，结果页时间戳保持新鲜）。
- `AppConfig`：删 `subLatencyMaxMs/TopN/Timeout/Workers/Probes/MinSuccessRate`、`subAutoUpdateRunLatency`；`subLatencyOutputFile` 改名 `landingOutputFile`（新键 `LANDING_OUTPUT_FILE`，旧键 `SUB_LATENCY_OUTPUT_FILE` 兜底迁移）。
- UI：运行页延迟按钮、配置页延迟滑块区（改「落地检测」区块）、引导页第 3 步延迟参数、托盘「运行延迟优选」、Ctrl+T 快捷键、导出 CSV 延迟列、编辑弹窗延迟输入框、theme 延迟配色全部移除。
- 保留的容错：`parseResultLines`/`ResultRow.latency` 仍可解析历史文件行尾的延迟字符串（只读兼容，不再是功能）。

当时的验证记录：`flutter analyze` 0 error、lib/ 零 warning；`flutter test` 243/243 通过。

## 3. 其它已删除的功能方向

- **带宽测速子系统**：早于延迟优选被彻底删除，曾残留 `maxSpeedMbps` 字段与带宽条，是「删功能要删干净」教训的来源。
- **代理测落地**（2026-09-29 用户定稿移除）：曾有「代理测落地 / 直连测落地」两个按钮与 `AppConfig.landingProxy`（键 `LANDING_PROXY`）。现落地检测只走直连并记录出口身份，旧键读取时忽略且不再写回。
- **国家筛选芯片与分组视图**（2026-10-02 移除）：`filterByCountries`/`countFacets` 相关测试与 `results_filter_chips_test.dart` 一并删除，只保留搜索、排序、编辑与落地历史。

## 4. 已解决的旧待确认事项

| 曾经的疑问 | 现状 |
|---|---|
| `githubRepo` 构造函数默认 `Hoffnungsschimmers/mnscn` 与 `fromJson` 兜底 `cf-ip` 分叉 | 两处统一为 `Hoffnungsschimmers/mnscn`，并有回归测试断言缺键兜底等于构造函数默认 |
| `.mimosa/` 未忽略 | 已写入 `.gitignore` |
| 本地工具脚本 `LandingProgress` 定义但无 UI 接线 | 该类型已不存在，取消与进度由 `TaskCancel` + 运行页阶段进度承担 |
| 远端仓库地址（`cfnb` → `dgbbsg`） | `origin` 与文档统一为 `Hoffnungsschimmers/dgbbsg` |
| 落地检测是否加并发 | 定稿保持串行，防 Cloudflare 限流 |
| CI analyze job 必红 | 根因是 `build_runner` 步骤（项目无 codegen），已删除；`test/` 里 3 个致命 warning 也已清零 |

## 5. 分支现状（2026-10-06 记录，未处理）

- 实际主线：`push-clean`，与 `origin/main` 同点。
- 本地 `main`（`8723274`，仍带延迟优选计划文档）与 `push-clean` **无共同祖先**，属另一条血脉。
- `refactor/hardening`、`feat/subscription-latency-ux`、`wip/ui-on-main-backup` 为陈旧分支，分别领先 29~74 个提交，无人认领。
- ROADMAP P0 的「分支归一」需要用户确认后才执行（删分支与重置 main 不可逆）。
