import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 密钥安全存储抽象：生产环境用系统安全存储（Windows DPAPI / Android
/// Keystore / macOS Keychain / iOS Keychain），测试注入内存实现。
abstract class SecureKV {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage 实现。
class SecureStorageKv implements SecureKV {
  const SecureStorageKv();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 测试用内存实现。
class InMemorySecureKv implements SecureKV {
  final Map<String, String> store = {};
  final List<String> writeLog = [];

  @override
  Future<String?> read(String key) async => store[key];

  @override
  Future<void> write(String key, String value) async {
    store[key] = value;
    writeLog.add(key);
  }

  @override
  Future<void> delete(String key) async {
    store.remove(key);
    writeLog.add('-$key');
  }
}
