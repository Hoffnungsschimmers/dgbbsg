import 'dart:io';

/// Reads the system proxy address (e.g. '127.0.0.1:10808') from the current
/// desktop platform's system settings.
///
/// Detection methods by platform:
/// - **Windows**: reads `HKCU\...\Internet Settings` registry keys
///   (`ProxyEnable` and `ProxyServer`).
/// - **macOS**: runs `networksetup -getwebproxy/getsecurewebproxy/
///   getsocksfirewallproxy "Wi-Fi"` and returns the first enabled proxy.
/// - **Linux**: checks environment variables (`http_proxy`, `https_proxy`,
///   `all_proxy` and their uppercase variants), then falls back to
///   `gsettings get org.gnome.system.proxy mode` for GNOME.
///
/// Returns `null` when no proxy is configured or on unsupported platforms.
/// All errors are silently swallowed so the caller never needs to handle them.
String? readSystemProxy() {
  try {
    if (Platform.isWindows) {
      return _readWindowsProxy();
    } else if (Platform.isMacOS) {
      return _readMacOsProxy();
    } else if (Platform.isLinux) {
      return _readLinuxProxy();
    }
  } catch (_) {
    // Silently ignore – proxy detection must never break the app.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Windows
// ---------------------------------------------------------------------------

/// Reads the HTTP proxy from the Windows registry.
///
/// Checks `ProxyEnable` under
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`.
/// When enabled, returns the value of `ProxyServer`.
String? _readWindowsProxy() {
  final enableResult = Process.runSync(
    'reg',
    [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
    ],
  );
  final enableMatch = RegExp(
    r'ProxyEnable\s+REG_DWORD\s+0x(\d+)',
  ).firstMatch(enableResult.stdout.toString());
  if (enableMatch == null || enableMatch.group(1) == '0') return null;

  final serverResult = Process.runSync(
    'reg',
    [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyServer',
    ],
  );
  final serverMatch = RegExp(
    r'ProxyServer\s+REG_SZ\s+(.+)',
  ).firstMatch(serverResult.stdout.toString());
  if (serverMatch == null) return null;
  final proxy = serverMatch.group(1)!.trim();
  return proxy.isNotEmpty ? proxy : null;
}

// ---------------------------------------------------------------------------
// macOS
// ---------------------------------------------------------------------------

/// Reads the proxy from macOS network preferences via `networksetup`.
///
/// Checks the following proxy types for the "Wi-Fi" service in order:
/// 1. HTTP proxy  (`-getwebproxy`)
/// 2. HTTPS proxy (`-getsecurewebproxy`)
/// 3. SOCKS proxy (`-getsocksfirewallproxy`)
///
/// For each, looks for "Enabled: Yes" followed by a "Server: host" line
/// and an optional "Port: port" line. Returns the first enabled proxy as
/// `host:port` (port defaults to `8080` when absent).
String? _readMacOsProxy() {
  const commands = [
    ['-getwebproxy', 'Wi-Fi'],
    ['-getsecurewebproxy', 'Wi-Fi'],
    ['-getsocksfirewallproxy', 'Wi-Fi'],
  ];

  for (final args in commands) {
    final result = Process.runSync('networksetup', args);
    final output = result.stdout.toString();
    final proxy = _parseMacOsNetworksetupOutput(output);
    if (proxy != null) return proxy;
  }
  return null;
}

/// Parses the output of a macOS `networksetup -get*proxy` command.
///
/// Expected format:
/// ```
/// Enabled: Yes
/// Server: 127.0.0.1
/// Port: 1080
/// ...
/// ```
String? _parseMacOsNetworksetupOutput(String output) {
  final lines = output.split('\n');
  String? enabled;
  String? server;
  String? port;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('Enabled:')) {
      enabled = trimmed.substring('Enabled:'.length).trim();
    } else if (trimmed.startsWith('Server:')) {
      server = trimmed.substring('Server:'.length).trim();
    } else if (trimmed.startsWith('Port:')) {
      port = trimmed.substring('Port:'.length).trim();
    }
  }

  if (enabled?.toLowerCase() != 'yes' || server == null || server.isEmpty) {
    return null;
  }
  return port != null && port.isNotEmpty ? '$server:$port' : '$server:8080';
}

// ---------------------------------------------------------------------------
// Linux
// ---------------------------------------------------------------------------

/// Reads the proxy from Linux environment variables or GNOME settings.
///
/// Environment variable priority (first match wins):
/// `http_proxy`, `https_proxy`, `all_proxy`, `HTTP_PROXY`, `HTTPS_PROXY`,
/// `ALL_PROXY`.
///
/// Values are expected in the form `http://host:port` or
/// `socks5://host:port`. The scheme prefix is stripped before returning.
///
/// If no environment variable is set, falls back to checking whether GNOME
/// proxy mode is set to "manual" via `gsettings`.
String? _readLinuxProxy() {
  // 1. Environment variables (highest priority).
  const envVars = [
    'http_proxy',
    'https_proxy',
    'all_proxy',
    'HTTP_PROXY',
    'HTTPS_PROXY',
    'ALL_PROXY',
  ];

  for (final name in envVars) {
    final value = Platform.environment[name];
    final parsed = _parseProxyEnvValue(value);
    if (parsed != null) return parsed;
  }

  // 2. GNOME / gsettings fallback.
  try {
    final result = Process.runSync(
      'gsettings',
      ['get', 'org.gnome.system.proxy', 'mode'],
    );
    final mode = result.stdout.toString().trim().replaceAll("'", '');
    if (mode != 'manual') return null;

    // When mode is manual, read the HTTP proxy host & port.
    final hostResult = Process.runSync(
      'gsettings',
      ['get', 'org.gnome.system.proxy.http', 'host'],
    );
    final portResult = Process.runSync(
      'gsettings',
      ['get', 'org.gnome.system.proxy.http', 'port'],
    );
    final host = hostResult.stdout.toString().trim().replaceAll("'", '');
    final port = portResult.stdout.toString().trim().replaceAll("'", '');
    if (host.isNotEmpty && port.isNotEmpty) return '$host:$port';
  } catch (_) {
    // gsettings may not be available on non-GNOME desktops.
  }

  return null;
}

/// Extracts `host:port` from a proxy environment variable value.
///
/// Accepts formats like:
/// - `http://127.0.0.1:8080`
/// - `socks5://127.0.0.1:1080`
/// - `127.0.0.1:8080` (already bare)
///
/// Returns `null` when [value] is `null`, empty, or unparseable.
String? _parseProxyEnvValue(String? value) {
  if (value == null || value.isEmpty) return null;

  // Strip scheme prefix if present (e.g. "http://", "socks5://").
  final schemeEnd = value.indexOf('://');
  final withoutScheme = schemeEnd >= 0 ? value.substring(schemeEnd + 3) : value;

  // Remove any trailing slashes or whitespace.
  final cleaned = withoutScheme.trim().replaceAll(RegExp(r'/+$'), '');
  return cleaned.isNotEmpty ? cleaned : null;
}

/// Parses a macOS `networksetup -get*proxy` output string.
///
/// This is a public wrapper of the internal parser to allow unit testing.
/// See [_parseMacOsNetworksetupOutput] for details.
String? parseMacOsNetworksetupOutput(String output) =>
    _parseMacOsNetworksetupOutput(output);

/// Parses a proxy environment variable value (e.g. `http://host:port`).
///
/// This is a public wrapper of the internal parser to allow unit testing.
/// See [_parseProxyEnvValue] for details.
String? parseProxyEnvValue(String? value) => _parseProxyEnvValue(value);
