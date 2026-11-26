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
    group("Setting Modification", () {
      void testTypedSet<T>(
        String name,
        Setting<T> Function() createSetting,
        T newValue,
      ) {
        test(name, () {
          final Setting<T> setting = createSetting();

          registry.register(setting);
          registry.set<T>(setting, newValue);

          expect(registry.get<T>(setting), equals(newValue));
          expect(registry.getByKey(setting.key), equals(newValue));
        });
      }

      void testDynamicSet<T>(
        String name,
        Setting<T> Function() createSetting,
        Object? newValue,
      ) {
        test(name, () {
          final Setting<T> setting = createSetting();

          registry.register(setting);
          registry.setByKey(setting.key, newValue);

          expect(registry.get<T>(setting), equals(newValue));
          expect(registry.getByKey(setting.key), equals(newValue));
        });
      }

      group("Typed set()", () {
        testTypedSet<bool>(
          "bool",
          () => Setting<bool>(
            key: "bool",
            title: "Boolean",
            defaultValue: false,
            fromJson: (value) => value as bool,
            toJson: (value) => value,
          ),
          true,
        );

        testTypedSet<int>(
          "int",
          () => Setting<int>(
            key: "int",
            title: "Integer",
            defaultValue: 0,
            fromJson: (value) => value as int,
            toJson: (value) => value,
          ),
          42,
        );

        testTypedSet<double>(
          "double",
          () => Setting<double>(
            key: "double",
            title: "Double",
            defaultValue: 0.0,
            fromJson: (value) => value as double,
            toJson: (value) => value,
          ),
          3.14,
        );

        testTypedSet<String>(
          "String",
          () => Setting<String>(
            key: "string",
            title: "String",
            defaultValue: "",
            fromJson: (value) => value as String,
            toJson: (value) => value,
          ),
          "Hello",
        );

        testTypedSet<List<String>>(
          "List<String>",
          () => Setting<List<String>>(
            key: "list",
            title: "String List",
            defaultValue: [],
            fromJson: (value) => List<String>.from(value as List),
            toJson: (value) => value,
          ),
          ["One", "Two"],
        );

        testTypedSet<Map<String, Object?>>(
          "Map<String, Object?>",
          () => Setting<Map<String, Object?>>(
            key: "map",
            title: "Map",
            defaultValue: {},
            fromJson: (value) => Map<String, Object?>.from(value as Map),
            toJson: (value) => value,
          ),
          {"name": "Test", "enabled": true},
        );

        testTypedSet<String?>(
          "String?",
          () => Setting<String?>(
            key: "nullable",
            title: "Nullable String",
            defaultValue: "Initial",
            fromJson: (value) => value as String?,
            toJson: (value) => value,
          ),
          null,
        );
      });

      group("Dynamic setByKey()", () {
        testDynamicSet<bool>(
          "bool",
          () => Setting<bool>(
            key: "bool",
            title: "Boolean",
            defaultValue: false,
            fromJson: (value) => value as bool,
            toJson: (value) => value,
          ),
          true,
        );

        testDynamicSet<int>(
          "int",
          () => Setting<int>(
            key: "int",
            title: "Integer",
            defaultValue: 0,
            fromJson: (value) => value as int,
            toJson: (value) => value,
          ),
          42,
        );

        testDynamicSet<double>(
          "double",
          () => Setting<double>(
            key: "double",
            title: "Double",
            defaultValue: 0.0,
            fromJson: (value) => value as double,
            toJson: (value) => value,
          ),
          3.14,
        );

        testDynamicSet<String>(
          "String",
          () => Setting<String>(
            key: "string",
            title: "String",
            defaultValue: "",
            fromJson: (value) => value as String,
            toJson: (value) => value,
          ),
          "Hello",
        );

        testDynamicSet<List<String>>(
          "List<String>",
          () => Setting<List<String>>(
            key: "list",
            title: "String List",
            defaultValue: [],
            fromJson: (value) => List<String>.from(value as List),
            toJson: (value) => value,
          ),
          ["One", "Two"],
        );

        testDynamicSet<Map<String, Object?>>(
          "Map<String, Object?>",
          () => Setting<Map<String, Object?>>(
            key: "map",
            title: "Map",
            defaultValue: {},
            fromJson: (value) => Map<String, Object?>.from(value as Map),
            toJson: (value) => value,
          ),
          {"name": "Test", "enabled": true},
        );

        testDynamicSet<String?>(
          "String?",
          () => Setting<String?>(
            key: "nullable",
            title: "Nullable String",
            defaultValue: "Initial",
            fromJson: (value) => value as String?,
            toJson: (value) => value,
          ),
          null,
        );
      });
    });
    group("Reset", () {
      void testReset<T>(
        String name,
        Setting<T> Function() createSetting,
        T changedValue,
      ) {
        test(name, () {
          final Setting<T> setting = createSetting();

          registry.register(setting);
          registry.set<T>(setting, changedValue);

          registry.reset<T>(setting);

          expect(registry.get<T>(setting), equals(setting.defaultValue));
        });
      }

      testReset<bool>(
        "bool",
        () => Setting<bool>(
          key: "reset_bool",
          title: "Boolean",
          defaultValue: false,
          fromJson: (value) => value as bool,
          toJson: (value) => value,
        ),
        true,
      );

      testReset<int>(
        "int",
        () => Setting<int>(
          key: "reset_int",
          title: "Integer",
          defaultValue: 0,
          fromJson: (value) => value as int,
          toJson: (value) => value,
        ),
        42,
      );

      testReset<double>(
        "double",
        () => Setting<double>(
          key: "reset_double",
          title: "Double",
          defaultValue: 0.0,
          fromJson: (value) => value as double,
          toJson: (value) => value,
        ),
        3.14,
      );

      testReset<String>(
        "String",
        () => Setting<String>(
          key: "reset_string",
          title: "String",
          defaultValue: "",
          fromJson: (value) => value as String,
          toJson: (value) => value,
        ),
        "Changed",
      );

      testReset<List<String>>(
        "List<String>",
        () => Setting<List<String>>(
          key: "reset_list",
          title: "List",
          defaultValue: ["Default"],
          fromJson: (value) => List<String>.from(value as List),
          toJson: (value) => value,
        ),
        ["Changed", "Value"],
      );

      testReset<Map<String, Object?>>(
        "Map<String, Object?>",
        () => Setting<Map<String, Object?>>(
          key: "reset_map",
          title: "Map",
          defaultValue: {"default": true},
          fromJson: (value) => Map<String, Object?>.from(value as Map),
          toJson: (value) => value,
        ),
        {"changed": true},
      );

      testReset<String?>(
        "String?",
        () => Setting<String?>(
          key: "reset_nullable",
          title: "Nullable String",
          defaultValue: "Default",
          fromJson: (value) => value as String?,
          toJson: (value) => value,
        ),
        null,
      );

      test("resetAll restores all registered settings", () {
        final Setting<bool> boolSetting = Setting<bool>(
          key: "all_bool",
          title: "Boolean",
          defaultValue: false,
          fromJson: (value) => value as bool,
          toJson: (value) => value,
        );

        final Setting<int> intSetting = Setting<int>(
          key: "all_int",
          title: "Integer",
          defaultValue: 0,
          fromJson: (value) => value as int,
          toJson: (value) => value,
        );

        final Setting<double> doubleSetting = Setting<double>(
          key: "all_double",
          title: "Double",
          defaultValue: 0.0,
          fromJson: (value) => value as double,
          toJson: (value) => value,
        );

        final Setting<String> stringSetting = Setting<String>(
          key: "all_string",
          title: "String",
          defaultValue: "",
          fromJson: (value) => value as String,
          toJson: (value) => value,
        );

        final Setting<List<String>> listSetting = Setting<List<String>>(
          key: "all_list",
          title: "List",
          defaultValue: ["Default"],
          fromJson: (value) => List<String>.from(value as List),
          toJson: (value) => value,
        );

        final Setting<Map<String, Object?>> mapSetting =
            Setting<Map<String, Object?>>(
              key: "all_map",
              title: "Map",
              defaultValue: {"default": true},
              fromJson: (value) => Map<String, Object?>.from(value as Map),
              toJson: (value) => value,
            );

        final Setting<String?> nullableSetting = Setting<String?>(
          key: "all_nullable",
          title: "Nullable",
          defaultValue: "Default",
          fromJson: (value) => value as String?,
          toJson: (value) => value,
        );

        registry.register(boolSetting);
        registry.register(intSetting);
        registry.register(doubleSetting);
        registry.register(stringSetting);
        registry.register(listSetting);
        registry.register(mapSetting);
        registry.register(nullableSetting);

        registry.set(boolSetting, true);
        registry.set(intSetting, 42);
        registry.set(doubleSetting, 3.14);
        registry.set(stringSetting, "Changed");
        registry.set(listSetting, ["Changed"]);
        registry.set(mapSetting, {"changed": true});
        registry.set<String?>(nullableSetting, null);

        registry.resetAll();

        expect(registry.get(boolSetting), false);
        expect(registry.get(intSetting), 0);
        expect(registry.get(doubleSetting), 0.0);
        expect(registry.get(stringSetting), "");
        expect(registry.get(listSetting), ["Default"]);
        expect(registry.get(mapSetting), {"default": true});
        expect(registry.get(nullableSetting), "Default");
      });
    });
    group("Save", () {
      void testSave<T>(
        String name,
        Setting<T> Function() createSetting,
        T value,
      ) {
        test(name, () async {
          final Setting<T> setting = createSetting();

          registry.register(setting);
          registry.set<T>(setting, value);

          await registry.save();

          final Map<String, Object?> saved = await registry.storage.read();

          expect(saved.containsKey(setting.key), true);
          expect(saved[setting.key], equals(value));
        });
      }

      testSave<bool>(
        "bool",
        () => Setting<bool>(
          key: "save_bool",
          title: "Boolean",
          defaultValue: false,
          fromJson: (value) => value as bool,
          toJson: (value) => value,
        ),
        true,
      );

      testSave<int>(
        "int",
        () => Setting<int>(
          key: "save_int",
          title: "Integer",
          defaultValue: 0,
          fromJson: (value) => value as int,
          toJson: (value) => value,
        ),
        42,
      );

      testSave<double>(
        "double",
        () => Setting<double>(
          key: "save_double",
          title: "Double",
          defaultValue: 0.0,
          fromJson: (value) => value as double,
          toJson: (value) => value,
        ),
        3.14,
      );

      testSave<String>(
        "String",
        () => Setting<String>(
          key: "save_string",
          title: "String",
          defaultValue: "",
          fromJson: (value) => value as String,
          toJson: (value) => value,
        ),
        "Hello",
      );

      testSave<List<String>>(
        "List<String>",
        () => Setting<List<String>>(
          key: "save_list",
          title: "List",
          defaultValue: [],
          fromJson: (value) => List<String>.from(value as List),
          toJson: (value) => value,
        ),
        ["One", "Two"],
      );

      testSave<Map<String, Object?>>(
        "Map<String, Object?>",
        () => Setting<Map<String, Object?>>(
          key: "save_map",
          title: "Map",
          defaultValue: {},
          fromJson: (value) => Map<String, Object?>.from(value as Map),
          toJson: (value) => value,
        ),
        {"name": "Test", "enabled": true},
      );

      testSave<String?>(
        "String?",
        () => Setting<String?>(
          key: "save_nullable",
          title: "Nullable String",
          defaultValue: "Default",
          fromJson: (value) => value as String?,
          toJson: (value) => value,
        ),
        null,
      );

      test("saving preserves unknown persisted keys", () async {
        await registry.initialize();

        final Setting<String> setting = Setting<String>(
          key: "save_preserve",
          title: "Preserve",
          defaultValue: "Default",
          fromJson: (value) => value as String,
          toJson: (value) => value,
        );

        registry.register(setting);
        registry.set(setting, "Changed");

        await registry.save();

        final Map<String, Object?> saved = await registry.storage.read();

        expect(saved["save_preserve"], "Changed");
      });
    });
  });
}
