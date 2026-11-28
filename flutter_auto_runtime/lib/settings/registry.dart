import 'package:flutter/foundation.dart';
import 'package:flutter_auto_runtime/settings/base.dart';
import 'package:flutter_auto_runtime/settings/group.dart';
import 'package:flutter_auto_runtime/settings/implementation/memory.dart';
import 'package:flutter_auto_runtime/settings/storage.dart';

class SettingsRegistry extends ChangeNotifier {
  SettingsRegistry({required this.storage});

  final SettingsStorage storage;

  final Map<String, SettingGroup> _groups = {};
  final Map<String, SettingBase> _settings = {};
  final Map<String, Object?> _values = {};

  Map<String, Object?> _persistedValues = {};

  bool _initialized = false;

  // -------------------------
  // Initialization
  // -------------------------

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _persistedValues = await storage.read();

    for (SettingBase setting in _settings.values) {
      if (_persistedValues.containsKey(setting.key)) {
        final Object? decoded = setting.decode(_persistedValues[setting.key]);

        final String? error = setting.validate(decoded);

        if (error != null) {
          throw FormatException(
            'Invalid stored setting "${setting.key}": $error',
          );
        }

        _values[setting.key] = decoded;
      }
    }

    _initialized = true;
    notifyListeners();
  }

  // -------------------------
  // Groups
  // -------------------------

  void registerGroup(SettingGroup group) {
    if (_groups.containsKey(group.key)) {
      throw StateError('Group "${group.key}" already exists.');
    }

    if (group.parentKey != null && !_groups.containsKey(group.parentKey)) {
      throw StateError('Parent group "${group.parentKey}" does not exist.');
    }

    _groups[group.key] = group;

    notifyListeners();
  }

  SettingGroup? getGroup(String key) {
    return _groups[key];
  }

  List<SettingGroup> get groups {
    return List.unmodifiable(_groups.values);
  }

  List<SettingBase> settingsInGroup(String groupKey) {
    return List.unmodifiable(
      _settings.values.where(
        (SettingBase setting) => setting.groupKey == groupKey,
      ),
    );
  }

  // -------------------------
  // Registration
  // -------------------------

  void register<T>(Setting<T> setting) {
    if (_settings.containsKey(setting.key)) {
      throw StateError('Setting "${setting.key}" already exists.');
    }

    if (setting.groupKey != null && !_groups.containsKey(setting.groupKey)) {
      throw StateError('Group "${setting.groupKey}" does not exist.');
    }

    final String? error = setting.validate(setting.defaultValue);

    if (error != null) {
      throw ArgumentError('Invalid default value for "${setting.key}": $error');
    }

    _settings[setting.key] = setting;
    _values[setting.key] = setting.defaultValue;

    // Support settings registered after initialization.
    if (_initialized && _persistedValues.containsKey(setting.key)) {
      final Object? decoded = setting.decode(_persistedValues[setting.key]);

      final String? storedError = setting.validate(decoded);

      if (storedError != null) {
        throw FormatException(
          'Invalid stored setting "${setting.key}": $storedError',
        );
      }

      _values[setting.key] = decoded;
    }

    notifyListeners();
  }

  SettingBase? definitionForKey(String key) {
    return _settings[key];
  }

  // -------------------------
  // Typed retrieval
  // -------------------------

  T get<T>(Setting<T> setting) {
    _requireRegistered(setting);

    return _values[setting.key] as T;
  }

  // -------------------------
  // Dynamic retrieval
  // -------------------------

  Object? getByKey(String key) {
    if (!_settings.containsKey(key)) {
      throw StateError('Unknown setting "$key".');
    }

    return _values[key];
  }

  // -------------------------
  // Typed modification
  // -------------------------

  void set<T>(Setting<T> setting, T value) {
    _requireRegistered(setting);

    _setValue(setting, value);
  }

  // -------------------------
  // Dynamic modification
  // -------------------------

  void setByKey(String key, Object? value) {
    final SettingBase? setting = _settings[key];

    if (setting == null) {
      throw StateError('Unknown setting "$key".');
    }

    _setValue(setting, value);
  }

  void _setValue(SettingBase setting, Object? value) {
    final String? error = setting.validate(value);

    if (error != null) {
      throw ArgumentError.value(value, setting.key, error);
    }

    if (_values[setting.key] == value) {
      return;
    }

    _values[setting.key] = value;

    notifyListeners();
  }

  void _requireRegistered<T>(Setting<T> setting) {
    final SettingBase? registered = _settings[setting.key];

    if (registered == null || !identical(registered, setting)) {
      throw StateError(
        'Setting "${setting.key}" is not registered '
        'with this registry.',
      );
    }
  }

  // -------------------------
  // Reset
  // -------------------------

  void reset<T>(Setting<T> setting) {
    set<T>(setting, setting.defaultValue);
  }

  void resetAll() {
    for (SettingBase setting in _settings.values) {
      _values[setting.key] = setting.defaultValue;
    }

    notifyListeners();
  }

  // -------------------------
  // Persistence
  // -------------------------

  Future<void> save() async {
    final Map<String, Object?> snapshot = Map<String, Object?>.from(
      _persistedValues,
    );

    for (SettingBase setting in _settings.values) {
      snapshot[setting.key] = setting.encode(_values[setting.key]);
    }

    await storage.write(snapshot);

    _persistedValues = snapshot;
  }

  @override
  void dispose() {
    super.dispose();
  }
  static SettingsRegistry FromMemory() {
    return SettingsRegistry(storage: MemorySettingsStorage());
  }
}
