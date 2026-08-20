# GitHub 同步管理页面 — 实施计划

## 目标

新增独立的「GitHub 同步」Tab，实现：
1. 从 GitHub 拉取远程结果文件
2. 在表格中查看/编辑/删除远程已有节点
3. 从本地结果文件中选择节点合并进来
4. 推送合并后的结果回 GitHub（增量合并，不覆盖未选中的远程节点）

## 文件变更清单

### 新建文件（2 个）
| 文件 | 说明 |
|------|------|
| `lib/features/github_sync/github_sync_state.dart` | 同步状态 + Riverpod notifier |
| `lib/features/github_sync/github_sync_tab.dart` | 同步页面 UI |

### 修改文件（3 个）
| 文件 | 变更 |
|------|------|
| `lib/core/github/github_push.dart` | 新增 `pullFile()` 方法 |
| `lib/app/app.dart` | 添加第 4 个 Tab「同步」 |
| `lib/app/shortcuts.dart` | 添加 `Ctrl+4` 快捷键 |

---

## 详细设计

### 1. `github_push.dart` — 新增 pullFile

```dart
/// 从 GitHub 拉取文件内容，返回 (content, sha)。
/// 文件不存在时返回 (null, null)。
Future<(String? content, String? sha)> pullFile(String path) async {
  final fileName = ...; // 同 pushFile 的文件名提取逻辑
  final url = '/repos/$repo/contents/$fileName';
  final resp = await _send(_req('GET', url));
  // 404 → (null, null)
  // 2xx → base64 decode content, 提取 sha
  return (content, sha);
}
```

### 2. `github_sync_state.dart` — 状态管理

**GithubSyncState:**
- `remoteNodes: List<ResultRow>` — 远程节点列表
- `remoteSha: String?` — 远程文件 SHA
- `loading / pushing / error` — UI 状态

**GithubSyncNotifier 核心方法:**
- `pullFromGithub()` — 拉取 → 解析 → 填充 remoteNodes
- `removeRemoteNode(i)` / `updateRemoteNode(i, raw)` / `addRemoteNode(raw)` — 编辑
- `mergeLocalNodes(localRows, {selectedIndices})` — 合并本地选中节点
  - 按 `ipPort` 去重：已存在→更新延迟，不存在→追加
- `pushToGithub()` — 序列化 → pushFile 推送

### 3. `github_sync_tab.dart` — UI 布局

**三区域单页：**

**A. 操作栏：** 「从 GitHub 拉取」按钮 + 状态指示

**B. 远程节点表格（主体）：**
- 复用 `ResultTable`（排序、延迟条形图、国旗）
- 编辑模式：行级编辑/删除 + 底部添加输入框
- 统计栏：节点数、国家分布、最低延迟
- 「合并本地节点」按钮 → 弹出选择对话框

**C. 底部：** 「推送到 GitHub」按钮 + 结果 toast

**合并对话框：**
- 本地文件选择（SegmentedButton）
- 本地节点表格 + Checkbox
- 全选/反选 + 「合并选中」按钮

### 4. `app.dart` — 注册第 4 Tab

- NavigationRail/Bar 添加 `Icons.sync` / '同步'
- IndexedStack 3→4 页
- nextTab/prevTab 循环 `% 3` → `% 4`

### 5. `shortcuts.dart` — Ctrl+4

```dart
const SingleActivator(LogicalKeyboardKey.digit4, control: true): const SwitchTabIntent(3),
```

---

## 合并逻辑

```
for each selectedLocalRow:
  if ipPort 已存在于 remoteNodes:
    → 更新该远程节点的 latency
  else:
    → 追加到 remoteNodes 末尾
```

效果：远程已有保留，本地选中的更新或追加，未选中的远程节点不动。

## 复用

- `ResultRow`、`parseResultLines()`、`ResultTable` 直接复用
- 配置 Tab 的 GitHub 设置不变
- 现有 Results Tab 的推送按钮保留

## 实施顺序

1. `github_push.dart` — 添加 pullFile
2. `github_sync_state.dart` — 创建状态
3. `github_sync_tab.dart` — 创建 UI
4. `app.dart` — 注册 Tab
5. `shortcuts.dart` — 快捷键