abstract interface class SettingsStorage {
  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> values);
}
