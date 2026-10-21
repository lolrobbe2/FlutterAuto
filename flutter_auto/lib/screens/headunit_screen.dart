import 'package:flutter/material.dart';

class HeadunitServerScreen extends StatelessWidget {
  const HeadunitServerScreen({super.key, required this.deviceSerial});

  final String deviceSerial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Head Unit Server')),
      body: Center(
        child: Text(
          'Head Unit Server\nDevice: $deviceSerial',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
