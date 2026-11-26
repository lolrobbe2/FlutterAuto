// Import the test package and Counter class
import 'package:flutter_auto_runtime/settings/base.dart';
import 'package:flutter_auto_runtime/settings/group.dart';
import 'package:flutter_auto_runtime/settings/implementation.dart/memory.dart';
import 'package:flutter_auto_runtime/settings/registry.dart';
import 'package:flutter_auto_runtime/settings/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("Registry Tests", () {
    final Map<String, SettingsStorage> storageImplementations = {
      'Memory': MemorySettingsStorage(),
    };
    storageImplementations.forEach(SettingsRegistryTests);
  });
}

void SettingsRegistryTests(String implementationName,SettingsStorage storage) {
  group('SettingsRegistry ${implementationName}', () {
    late SettingsRegistry registry;

    setUp(() {
      registry = SettingsRegistry(storage: storage);
    });

    tearDown(() {
      registry.dispose();
    });
    group("Default State", () {
      test("Groups should be empty", () {
        List<SettingGroup> groups = registry.groups;
        expect(groups.isEmpty, true);
      });
      test("Unknown groups should return null", () {
        expect(registry.getGroup("unknown"), isNull);
      });

      test("Settings in any group should be empty", () {
        expect(registry.settingsInGroup("unknown"), isEmpty);
      });

      test("Setting definitions should be empty", () {
        expect(registry.definitionForKey("unknown"), isNull);
      });

      test("Getting an unknown setting should throw", () {
        expect(() => registry.getByKey("unknown"), throwsStateError);
      });
    });
    group("Setting Registration - Types", () {
      test("bool", () {
        final Setting<bool> setting = Setting<bool>(
          key: "bool",
          title: "Boolean",
          defaultValue: true,
          fromJson: (value) => value as bool,
          toJson: (value) => value,
        );

        registry.register(setting);

        expect(registry.get(setting), true);
      });

      test("int", () {
        final Setting<int> setting = Setting<int>(
          key: "int",
          title: "Integer",
          defaultValue: 42,
          fromJson: (value) => value as int,
          toJson: (value) => value,
        );

        registry.register(setting);

        expect(registry.get(setting), 42);
      });

      test("double", () {
        final Setting<double> setting = Setting<double>(
          key: "double",
          title: "Double",
          defaultValue: 3.14,
          fromJson: (value) => value as double,
          toJson: (value) => value,
        );

        registry.register(setting);

        expect(registry.get(setting), 3.14);
      });

      test("String", () {
        final Setting<String> setting = Setting<String>(
          key: "string",
          title: "String",
          defaultValue: "Hello",
          fromJson: (value) => value as String,
          toJson: (value) => value,
        );

        registry.register(setting);

        expect(registry.get(setting), "Hello");
      });

      test("List<String>", () {
        final Setting<List<String>> setting = Setting<List<String>>(
          key: "list",
          title: "String List",
          defaultValue: ["One", "Two", "Three"],
          fromJson: (value) => List<String>.from(value as List),
          toJson: (value) => value,
        );

        registry.register(setting);

        expect(registry.get(setting), ["One", "Two", "Three"]);
      });

      test("Map<String, Object?>", () {
        final Setting<Map<String, Object?>> setting =
            Setting<Map<String, Object?>>(
              key: "map",
              title: "Object Map",
              defaultValue: {"name": "Test", "enabled": true, "count": 42},
              fromJson: (value) => Map<String, Object?>.from(value as Map),
              toJson: (value) => value,
            );

        registry.register(setting);

        expect(registry.get(setting), {
          "name": "Test",
          "enabled": true,
          "count": 42,
        });
      });
    });
  });
}
