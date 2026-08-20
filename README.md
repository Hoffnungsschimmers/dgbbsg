# CF优选工具 (cfnb_app)

Cloudflare 边缘节点优选工具的 **Flutter 跨端重写版**（Windows + 安卓一套代码）。

> 旧版为 Python + tkinter（`cfnb` 仓库）。本仓库用 Dart 重写全部业务逻辑，
> 目标：真正可分发的原生软件（Windows 单文件/安装包、安卓 APK/AAB），
> 摆脱"依托项目文件夹 + pythonw 启动"，并解决 tkinter 卡顿/拖影。

## 技术栈

- Flutter 3.x / Dart 3.x
- 状态管理：`flutter_riverpod`
- 存储：`shared_preferences` + `path_provider`（配置/历史落应用私有目录）
- 网络：`dio`
- 测速/探测：`dart:io` Socket + HttpClient
- 图表（规划）：`fl_chart`

## 架构

```
lib/
├─ core/        # 纯业务逻辑，无 UI 依赖，可单测、可 Isolate 隔离
│  ├─ config/       # AppConfig 模型 + 持久化
│  ├─ fetch/        # 节点源拉取 + 文本/JSON/RIPE 解析
│  ├─ latency/      # TCP 延迟探测 + 优选 + 历史
│  ├─ speed/        # 带宽测速（两轮漏斗 + 重试）
│  ├─ subscription/ # 订阅解析(vmess/ss/trojan...) + 禁用状态
│  ├─ output/       # 写 ip.txt + 摘要
│  ├─ github/       # 推送到独立 cf-ip 仓库
│  └─ pipeline/     # 6 阶段编排（对应旧 _run_all）
└─ features/     # UI 层（运行/订阅器/设置/结果）
```

## 开发

```powershell
. .\env.ps1                 # 启用 Flutter + 代理(127.0.0.1:7890)
flutter pub get
flutter test                # 全部单测（core 60 项 + UI widget 6 项）
flutter analyze             # 0 error / 0 warning
flutter run -d windows      # 调试运行桌面（需 VS C++ 桌面负载 + 开发者模式）
```

## 打包发布（Windows）

前置（仅需一次）：

1. 安装 **Visual Studio 2022 Community** + 工作负载 **"使用 C++ 的桌面开发"**（含 MSVC / Windows SDK / CMake）。
2. 开启 **开发者模式**：`ms-settings:developers` → 打开"开发人员模式"（Flutter 构建插件需 symlink 权限）。
3. 以**管理员**身份打开 PowerShell 执行打包脚本：

```powershell
.\scripts\build_windows.ps1
```

脚本产出（位于仓库根 / `build\windows\x64\runner\Release`）：

| 产物 | 说明 |
| --- | --- |
| `CFYXX.msix` | MSIX 安装包（自签名测试证书，双击安装；如需商店发布请替换正式证书） |
| `CFYXX-<版本>-portable.zip` | 可移植版：解压即用的 Release 文件夹（exe + flutter_windows.dll + dartjni.dll + data/） |

> msix 默认用自签名 `test_certificate.pfx`，安装时 Windows 会提示"未知发布者"，可照常安装；
> 正式分发请配置 `msix_config` 中的正式证书与 `publisher`/`identity_name`。

## 当前进度

- [x] P1 核心层（config/fetch/latency/output/speed/subscription/github/pipeline），**60+ 单测全绿**
- [x] P2 UI 层（运行页 stepper + 指标卡 + 可拖拽/可折叠日志抽屉；设置/订阅器/结果页；Edge Telemetry 橙主题）
- [x] P3 Windows 桌面构建（VS C++ 桌面负载 + 开发者模式）✅ 真机构建 + 运行验证通过
- [x] P5 打包（Win msix 安装包 + 可移植 zip，见上）
- [ ] P4 安卓适配与构建（需 Android SDK；APK/AAB 待做）

## GitHub 数据隔离

IP 数据仍推送到独立的 `cf-ip` 仓库（与代码仓库隔离），由 `core/github` 调用
GitHub Contents API 完成，token 不落盘明文。
