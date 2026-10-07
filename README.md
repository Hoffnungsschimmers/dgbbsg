# CFNB / CF优选工具

Windows 为主要使用平台的 Flutter 应用：获取订阅中的地址 → 检测当前网络的 Cloudflare POP → 保存结果 → 按质量门槛推送 GitHub。当前版本 **1.1.0+2**。

## 使用

1. 在配置页填写订阅源。GitHub Token、仓库和分支只在需要推送时填写。
2. 运行页可分步获取、检测，也可执行一键全流程。进度显示当前阶段和处理数量，可停止任务。
3. 结果页每行注明 POP 实测、GeoIP 估计或原始标注；支持搜索、排序、拖拽调序、行编辑与「原始内容」整段编辑，改错了可撤销/重做（最多 30 步）。整段编辑**逐行**校验，任一行不是 `地址:端口` 就整批拒绝并指出第几行；改过地址的行会清空其落地证据，需重测。有未保存修改时会提示确认，不会静默重载。国家分类芯片和分组已移除。
4. 推送保护默认要求至少 1 个有效节点、至少 50% 的独立 IP 有 POP 实测，节点数量不少于推送基线的 50%。在配置页 GitHub 区块中调整。被拦截的结果仍保存在本地；再次运行不会自动重置推送基线。
5. 结果被替换或编辑前保留本地快照，结果页“恢复历史结果”选择快照恢复；恢复前也会备份当前文件。
6. 定时任务支持仅获取、获取并检测、完整流程三种模式。仅在软件运行期间生效，关闭到托盘仍运行，退出软件后停止；已有任务时跳过，不排队重叠。

Cloudflare trace 的 POP 映射是本轮观测。GeoIP 是数据库估计，缓存有效期为 7 天，不能证明实际 POP。启用 TUN 时，“直连”也可能被代理客户端规则接管；运行日志记录本轮出口身份。

CSV 和 TXT 可以直接作为地址结果使用。Clash、V2Ray 和 sing-box 导出是**配置模板**，缺少真实协议、密码、UUID 与 TLS 参数，必须手动补齐。

WebDAV 配置备份排除 GitHub Token、Webhook URL、WebDAV 密码、订阅链接、订阅器清单和节点 UUID；恢复保留本机这些内容。旧版备份中的明文凭据不会因升级自动从云盘删除。结果文件的备份与恢复支持自定义绝对路径。同步状态显示在运行页和同步入口。

日志先脱敏再进入内存和磁盘，支持运行页导出；应用支持目录下 `logs/` 按天滚动、保留 7 天，每个日志文件超过 1 MB 后轮换一次。

## 开发与打包

本机验证环境：Flutter 3.44.6 / Dart 3.12.2；CI 固定 Flutter 3.44.6。Windows 构建需要 Visual Studio C++ 桌面开发工具链（含 ATL 组件）。

质量基线（2026-10-07 实测）：`flutter analyze --no-fatal-infos` 为 0 error / 0 warning / 201 info，`flutter test` 为 351/351 全绿（39 个测试文件）。两者都过才算改完。全量并行跑若只在 tearDown 删临时目录时抛 `PathAccessException errno=32`，是 Windows 句柄占用，不是用例回归。

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter test
./scripts/package-windows.ps1
# 本机 SDK 不在 PATH 时：
./scripts/package-windows.ps1 -Flutter D:\env\flutter\bin\flutter.bat
```

便携包需要整体解压，再运行 `cfnb_app.exe`，不要只复制 EXE。配置和结果仍使用系统应用数据/文档目录；“便携包”指免安装分发，并非所有数据保存在 EXE 旁。

## 文档地图

- 本文件：怎么用、怎么打包、有哪些注意事项。
- [`PROJECT_OVERVIEW.md`](PROJECT_OVERVIEW.md)：权威技术总览——架构、数据流、配置字段、测试语义、构建环境的坑与硬教训。动代码前读它。
- [`docs/RELEASE_NOTES.md`](docs/RELEASE_NOTES.md)：逐版本变更。
- `docs/IMPLEMENTATION_*.md`：逐轮验收记录（做了什么、验了什么、哪些没验）。
- [`docs/ROADMAP.md`](docs/ROADMAP.md)：规划与遗留事项，含红线（哪些决定不能推翻）。
- [`docs/archive/PROJECT_HISTORY.md`](docs/archive/PROJECT_HISTORY.md)：历史沿革与已删功能，仅供追溯。

Android 保留工程与 CI 构建，但至今未做真机验收或正式签名配置（APK 用 debug key）。
