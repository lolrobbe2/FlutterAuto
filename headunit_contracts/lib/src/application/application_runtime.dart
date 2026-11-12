import 'application_instance.dart';
import 'application_launch_context.dart';
import 'application_manifest.dart';
import 'application_runtime_kind.dart';

abstract interface class ApplicationRuntime {
  ApplicationRuntimeKind get kind;

  Future<ApplicationInstance> createInstance({
    required ApplicationManifest manifest,
    required ApplicationLaunchContext context,
  });
} 