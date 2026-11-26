import 'package:flutter_auto_runtime/settings/storage.dart';

class MemorySettingsStorage implements SettingsStorage {
  final Map<String, Object?> _values = {};

  @override
  Future<Map<String, Object?>> read() async {
    return Map<String, Object?>.from(_values);
  }

  @override
  Future<void> write(Map<String, Object?> values) async {
    _values
      ..clear()
      ..addAll(values);
  }
}
