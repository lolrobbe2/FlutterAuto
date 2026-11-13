import '../modules/module_id.dart';
import 'product_json_helpers.dart';
import 'product_package_path.dart';

class ProductModule {
  final ModuleId id;
  final String packagePath;
  final bool enabled;

  ProductModule({
    required this.id,
    required this.packagePath,
    this.enabled = true,
  }) {
    validateProductPackagePath(packagePath);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id.value,
      'packagePath': packagePath,
      'enabled': enabled,
    };
  }

  factory ProductModule.fromJson(Map<String, Object?> json) {
    return ProductModule(
      id: ModuleId(productReadRequiredString(json, 'id')),
      packagePath: productReadRequiredString(json, 'packagePath'),
      enabled: productReadOptionalBool(json, 'enabled', defaultValue: true),
    );
  }
}
