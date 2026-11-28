import 'package:flutter_auto_runtime/navigation/status/status_icon.dart';
import 'package:material_ui/material_ui.dart';

class WifiStatusIcon extends StatusIcon {
  const WifiStatusIcon({super.key, super.visible});

  @override
  void onClicked() {
    debugPrint('WiFi clicked');
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.wifi, size: 20),
    );
  }
}

class BluetoothStatusIcon extends StatusIcon {
  const BluetoothStatusIcon({super.key, super.visible});

  @override
  void onClicked() {
    debugPrint('Bluetooth clicked');
  }

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.bluetooth, size: 20),
    );
  }
}

class GpsStatusIcon extends StatusIcon {
  const GpsStatusIcon({super.key, super.visible});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.gps_fixed, size: 20),
    );
  }
}

class BatteryStatusIcon extends StatusIcon {
  const BatteryStatusIcon({super.key, super.visible});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.battery_full, size: 20),
    );
  }
}