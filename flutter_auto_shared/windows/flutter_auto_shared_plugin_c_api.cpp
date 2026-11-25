#include "include/flutter_auto_shared/flutter_auto_shared_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "flutter_auto_shared_plugin.h"

void FlutterAutoSharedPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_auto_shared::FlutterAutoSharedPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
