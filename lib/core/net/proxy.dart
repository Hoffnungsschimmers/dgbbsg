import 'dart:io';

/// 从 Windows 注册表读取系统代理地址（如 '127.0.0.1:10808'）。
/// 非 Windows 平台或代理未启用时返回 null。
/// 读取失败静默返回 null（不影响主流程）。
String? readWindowsSystemProxy() {
  if (!Platform.isWindows) return null;
  try {
    final enableResult = Process.runSync(
      'reg', ['query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyEnable'],
    );
    final enableMatch = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x(\d+)').firstMatch(enableResult.stdout.toString());
    if (enableMatch == null || enableMatch.group(1) == '0') return null;

    final serverResult = Process.runSync(
      'reg', ['query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v', 'ProxyServer'],
    );
    final serverMatch = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)').firstMatch(serverResult.stdout.toString());
    if (serverMatch == null) return null;
    final proxy = serverMatch.group(1)!.trim();
    return proxy.isNotEmpty ? proxy : null;
  } catch (_) {
    return null;
  }
}
