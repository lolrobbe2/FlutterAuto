import 'package:flutter/material.dart';
import 'package:flutter_auto/screens/device_selection_screen.dart';
import 'package:flutter_auto/services/adb_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final adb = AdbManager();
  try {
    await adb.initializeAndroidAutoLink();
    // Nu kun je je Socket.connect('127.0.0.1', 5277) openen om de Protobufs te streamen!
  } catch (e) {
    print('Fout tijdens initialisatie: $e');
  }
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const DeviceSelectionScreen(),
    );
  }
}
