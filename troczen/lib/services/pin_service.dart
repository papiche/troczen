import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PinService {
  static const _pinKey = 'app_pin_hash';
  static const _attemptsKey = 'app_pin_failures';
  static const int maxAttempts = 3;
  static const int pinLength = 4;

  final _storage = const FlutterSecureStorage();

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _pinKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    final hash = sha256.convert(utf8.encode(pin)).toString();
    await _storage.write(key: _pinKey, value: hash);
    await _storage.write(key: _attemptsKey, value: '0');
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;
    final hash = sha256.convert(utf8.encode(pin)).toString();
    return hash == storedHash;
  }

  Future<int> getFailureCount() async {
    final val = await _storage.read(key: _attemptsKey);
    return int.tryParse(val ?? '0') ?? 0;
  }

  Future<int> recordFailure() async {
    final count = await getFailureCount() + 1;
    await _storage.write(key: _attemptsKey, value: count.toString());
    return count;
  }

  Future<void> resetFailures() async {
    await _storage.write(key: _attemptsKey, value: '0');
  }

  Future<void> removePin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _attemptsKey);
  }
}
