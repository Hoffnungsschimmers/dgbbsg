# 2026-10-06 整理轮记录

本轮范围：把「全面了解并整理项目」落到仓库里——补记未归档的一轮开发、提交长期悬空的工作区、
清掉根目录产物、文档收敛为两份、拆分最大的 UI 文件、按当前代码重新出包。**没有新增产品功能**。

## 做了什么

- **文档**：`PROJECT_CONTEXT.md`（旧路径、3 Tab、延迟优选）与 `HANDOVER.md`（未入库、内容大半过时）删除，
  其硬教训 PROJECT_OVERVIEW §10 早已收录；历史沿革与已删功能进 `docs/archive/PROJECT_HISTORY.md`；
  README 与 PROJECT_OVERVIEW 补上 10-03 的结果页编辑轮与实测基线；ROADMAP 的 P0 逐条复核标注。
- **工作区**：1.1.0+2 整轮（含 10-03 编辑轮）此前**只存在于工作区**，已按主题提交（见下方提交列表）。
- **产物**：删 6 个旧 `CFYXX-*` 包（zip/apk/msix）、7 个 `.codex-*.log`、2 个 `tmp-*.log`、
  7 月的 `history/` 快照与根目录 `ip.txt`/`addressesapi*.txt` 样本；保留最新 CFNB 1.1.0+2 便携包。
  `.gitignore` 补 `CFNB-*.zip` / `*-windows-portable*.zip` / `*.apk` / `*.zip.sha256`——
  原规则只挡 `CFYXX-*.zip`，新包名的 27MB zip 处于「未忽略」状态，一次 `git add -A` 就会进历史。
- **行尾**：`git ls-files --eol` 查出 `subscription_converter_test.dart` 是 `c417a28` 统一行尾时的漏网
  （index 仍为 CRLF），单独一个纯行尾提交补上；现全仓 index 无 CRLF/mixed。
- **拆文件（第一批）**：`config_tab.dart` 抽出 `config_entries.dart`（订阅器/订阅链接条目纯解析，
  新增 `config_entries_test.dart` 12 条，含「备注含 `://`」「节点链接不拼备注」「拆拼往返」）与
  `config_item_widgets.dart`（卡片/编辑弹窗/批量小标签/批量粘贴，仅把 State 的 `context` 变显式参数）。
  1383 → 1069 行。
- **拆文件（第二批）**：`results_tab.dart` 迁出 `result_edit_dialog.dart`（编辑节点弹窗，`ref` 与
  `_saveEdits` 以参数传入，校验与 toast 语义不变）、`result_raw_view.dart`（原始内容视图，控制器仍归
  State，`onChanged` 回调让父级重建以刷新「全部复制」按钮可用态）、`landing_history_dialog.dart`
  （落地历史面板，连文档注释一起搬）。1309 → 1032 行；顺带删掉空转的 `core/net/endpoint.dart` 与
  `core/net/landing_history.dart` import——`unused_import` 是 warning 级，留着就打破 0 warning 基线。
- **拆文件（决定不做）**：`subscriptions_state.dart`（964 行）不拆；两个 UI 文件剩下的部分
  （`_compactTextField`、视图切换、工具栏、快照与推送流程）与 `_save`、控制器回填、`_rawView`/`_restoring`
  同生命周期，硬拆只是把耦合换成一大串参数，还会碰 `ref.listenManual` 那个坑。理由记在 PROJECT_OVERVIEW §9。
- **测试稳定性**：全量并行跑偶发 `pipeline_reliability_test` 在 tearDown 删临时目录时抛
  `PathAccessException errno=32`（Windows 句柄未释放），单跑恒过。新增 `test/helpers/temp_dir.dart`
  的 `removeTempDir`（重试后放弃），5 个纯 `test()` 文件的 9 处清理改用它；
  当时判断「widget 用例不能带延迟重试」所以留了 4 处未动——**该判断后来被实测推翻**，见下文 10-07 续。

> 本节数字是 10-06 当晚的阶段值；跨到 10-07 的最终基线为 `flutter test` **351/351**、
> `flutter analyze` **0 error / 0 warning / 201 info**，见「10-07 续」与 PROJECT_OVERVIEW 头部。

## 验证状态

- `flutter test`：**348/348 通过**（38 个测试文件；两批拆分前后各跑一次全量）。
- `flutter analyze --no-fatal-infos`：**0 error、0 warning、204 info**，退出码 0（拆分前后条数一致）。
- `git diff --check`：通过；`git ls-files --eol`：index 与工作区均无 CRLF/mixed。
- 中间提交可编译性是**实测**的：临时 worktree 检出「core 提交但不含 features」得到 analyze 退出码 1 +
  `reliability_test` 加载失败（`ResultRow.evidence`、`ResultState.qualityIssue` 等符号双向依赖），
  故放弃 core/UI 两刀切法，合为一个已验证的提交。
- 拆分只改文件组织、未改行为；判据是同一套 348 条用例（含 `results_tab_test`、`result_editing_test`、
  `results_landing_history_test`、`ip_count_box_test`、`config_tab_test`、`config_backfill_test`）保持全绿。

## 边界（没做）

- 没动 Git 分支拓扑：本地 `main`（8723274，与 `push-clean` 无共同祖先）与
  `refactor/hardening`、`feat/subscription-latency-ux`、`wip/ui-on-main-backup` 全部原样保留。
- 没有 push、没有打 tag、没有 GitHub Release。
- 没有升级依赖、没有改产品行为、没有新增配置字段。
- 未做原生窗口逐项视觉验收（控件与异常路径靠 Flutter 用例覆盖）。

## 10-07 续：结果页拆分、一个真 bug 与重新出包

- **拆文件**：`results_tab.dart` 1309 → 1032 行（`result_edit_dialog.dart`、`result_raw_view.dart`、
  `landing_history_dialog.dart`）。
- **修 bug（`25a0ff7`）**：给拆出的界面写 widget 用例时，第一次进入编辑模式就撞上
  「Every item of ReorderableListView must have a key」——数据行的 key 挂在 `_DataRowWidget` 上，
  外面却还套着 `.animate().fadeIn().slideX()`，`ReorderableListView` 看到的是无 key 的 `Animate`。
  后果是编辑模式下操作列渲染不出来、点行打不开弹窗，即**除拖拽排序外的全部行编辑入口都不可用**。
  这是 10-03 加拖拽排序时引入的，`result_editing_test.dart` 只测 notifier 层，界面接线没人兜。
  修法：key 提到 `KeyedSubtree` 上（`_DataRowWidget` 的 key 参数随之删除，否则破 0 warning）。
  已做反证：把 `results_table.dart` 换回修复前版本跑同一条用例，断言照常抛出。
- **纠正上一轮的错误结论**：我在 `780f1d6` 的提交说明里写「`testWidgets` 里加延迟重试会超时」，
  实测不成立——仓库的 `results_tab_test` 本来就在 widget 用例的 `addTearDown` 里跑 5 次重试，
  新加的 `results_editing_ui_test` 也在 `testWidgets` 里用 `removeTempDir` 通过。
  已把 4 处手写重试/吞异常统一到 `removeTempDir`（`fd3c304`），并顺手拆掉
  `webdav_sync_panel_test` 里 `createTemp(...) ?? Directory.systemTemp` 的回退——
  它一旦触发就会让 tearDown 去删系统临时目录根，只是被 `catch (_) {}` 静默吞掉。
  提交说明不能改写，以本节为准。

### 重新出包（当前代码）

- 构建：`flutter build windows --release` 55.6 秒内完成（`scripts/package-windows.ps1` 驱动，
  CMake 生成器为 VS 17 2022 BuildTools，无遗留 VS-18 缓存；构建前确认没有托盘常驻实例）。
- 产物：`D:\cfnb\CFNB-1.1.0+2-windows-portable-20261007-113539.zip`，25.86 MiB，31 个条目，
  无 `.msix` 混入，含 `RELEASE_NOTES.md`。
- SHA-256：`4E49EF39EA860FDB42825149F87F8D3184F7BFA48000683E7142C8E473322950`
  （同名 `.sha256` 文件重算一致）。
- 新鲜度证据链：修复提交 `25a0ff7` 时间 11:34:34 → `data/app.so` 11:35:36 → zip 11:35:44；
  包内 `data/app.so` 与构建目录内 `data/app.so` 同为
  `83C977DE74AA007F658BCEF3CB3CEB8AC6E55E6CBDB570CBF87F723C2CBCBE25`；打包后 `lib/` 与
  `pubspec.yaml` 无未提交改动，所以包=已提交代码。
- 对比旧包：10-02 的 `app.so`（`4153fddb…`）里没有 `撤销`/`重做`/`第 N 行不是有效的地址:端口`
  这三个 UTF-16 字符串（计数 0），新包各为 1 —— 说明 10-03 的结果页编辑轮此前从未进过任何发布包，
  而旧包带的是**没有编辑崩坏的旧界面**。
- 启动核验：从 `D:\cfnb\dist\CFNB-1.1.0+2-20261007-113539\cfnb_app.exe` 启动，
  PID 38528、`Responding=True`、窗口标题 21 字符（`CFNB - CF优选工具 1.1.0+2`）、工作集 136.8 MiB，
  检查后已停止进程。未做原生窗口逐项点击；编辑模式的界面接线由上述 widget 用例证明。
- 中间产物清理：删除了 11:04 那次构建的 zip 与 `dist/` 目录（它带的是修复前的编辑模式，留着会误导）；
  10-02 的旧包按用户「保留旧的最新包」意图仍在根目录。

## 提交列表（push-clean，未推送）

| 提交 | 内容 |
|---|---|
| `4540f2f` | chore: 版本 1.1.0+2、CI 钉 SDK、便携打包脚本、gitignore 堵二进制 |
| `8c58b0e` | feat: 1.1.0+2 可靠性轮与结果页编辑（进度取消、推送门槛、安全读写、撤销重做） |
| `fd51090` | docs: 收敛为 README + PROJECT_OVERVIEW 两份活文档，历史内容归档 |
| `9e2b494` | chore: 补漏——把最后一个 CRLF 入库文件统一为 LF |
| `cba6d11` | refactor: 配置页拆出条目解析与条目控件，1383 → 1069 行，解析逻辑补 12 条直测 |
| `780f1d6` | test: 临时目录清理改为容忍 Windows 句柄占用，全量跑不再偶发假失败 |
| `1b1f919` | refactor: 结果页拆出编辑弹窗、原始内容视图与落地历史面板（1309 → 1032） |
| `25a0ff7` | fix: 编辑模式整块崩（ReorderableListView 缺 key）+ 三条界面级用例 |
| `fd3c304` | test: 临时目录清理统一到 removeTempDir，拆掉会删 %TEMP% 根的回退 |

（`cba6d11` 说明里的「1021 行」是按删除行数推算的错值，实际 1069 行；未 amend，以本文件为准。）
