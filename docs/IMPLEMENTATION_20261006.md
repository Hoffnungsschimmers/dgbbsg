# 2026-10-06 整理轮记录

本轮范围：把「全面了解并整理项目」落到仓库里——补记未归档的一轮开发、提交长期悬空的工作区、
清掉根目录产物、文档收敛为两份、拆分最大的 UI 文件。**没有新增产品功能**。

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
- **拆文件**：`config_tab.dart` 抽出 `config_entries.dart`（订阅器/订阅链接条目纯解析，
  新增 `config_entries_test.dart` 12 条，含「备注含 `://`」「节点链接不拼备注」「拆拼往返」）与
  `config_item_widgets.dart`（卡片/编辑弹窗/批量小标签/批量粘贴，仅把 State 的 `context` 变显式参数）。
  1383 → 1069 行。`_compactTextField` 与定时/GitHub/Webhook/WebDAV 区块留在原文件：与 `_save`、
  控制器回填同生命周期，硬拆会踩 `ref.listenManual` 那个坑。
- **测试稳定性**：全量并行跑偶发 `pipeline_reliability_test` 在 tearDown 删临时目录时抛
  `PathAccessException errno=32`（Windows 句柄未释放），单跑恒过。新增 `test/helpers/temp_dir.dart`
  的 `removeTempDir`（重试后放弃），5 个纯 `test()` 文件的 9 处清理改用它；
  3 个 widget 测试文件的 4 处**不改**——`testWidgets` 的 fake async 区里 `Future.delayed` 不 pump 就超时。

## 验证状态

- `flutter test`：**348/348 通过**（38 个测试文件，2026-10-06 本轮最终全量）。
- `flutter analyze --no-fatal-infos`：**0 error、0 warning、204 info**，退出码 0。
- `git diff --check`：通过；`git ls-files --eol`：index 与工作区均无 CRLF/mixed。
- 中间提交可编译性是**实测**的：临时 worktree 检出「core 提交但不含 features」得到
  analyze 退出码 1 + `reliability_test` 加载失败（`ResultRow.evidence`、`ResultState.qualityIssue`
  等符号双向依赖），故放弃 core/UI 两刀切法，合为一个已验证的提交。
- 本轮未重新构建 Windows Release、未重新打包便携包：便携包是 10-02 23:00 的产物，
  其后的改动（10-03 编辑轮 + 本轮拆分）**不在包里**；本轮只改了 UI 文件的组织方式，
  未改行为，但包与仓库已有差异这一事实需要知道。

## 边界（没做）

- 没动 Git 分支拓扑：本地 `main`（8723274，与 `push-clean` 无共同祖先）与
  `refactor/hardening`、`feat/subscription-latency-ux`、`wip/ui-on-main-backup` 全部原样保留。
- 没有 push、没有打 tag、没有 GitHub Release。
- 没有升级依赖、没有改产品行为、没有新增配置字段。
- `results_tab.dart`（1309 行）与 `subscriptions_state.dart`（964 行）未拆。
- 本轮记录用文字与提交说明留存，未做原生窗口逐项视觉验收。

## 提交列表（push-clean，未推送）

| 提交 | 内容 |
|---|---|
| `4540f2f` | chore: 版本升至 1.1.0+2，固定 CI SDK 并新增便携打包脚本 |
| `8c58b0e` | feat: 1.1.0+2 可靠性轮与结果页编辑（进度取消、推送门槛、安全读写、撤销重做） |
| `fd51090` | docs: 收敛为 README + PROJECT_OVERVIEW 两份活文档，历史内容归档 |
| `9e2b494` | chore: 补漏——把最后一个 CRLF 入库文件统一为 LF |
| `cba6d11` | refactor: 配置页拆出条目解析与条目控件，1383 行降到 1069 行并给解析逻辑补单测 |
| `780f1d6` | test: 临时目录清理改为容忍 Windows 句柄占用，全量跑不再偶发假失败 |

（`cba6d11` 的说明里写的「1021 行」是当时按删除行数推算的错值，实际为 1069 行。）
