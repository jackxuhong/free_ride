import 'package:flutter/material.dart';
import 'package:free_ride/screens/devices_screen.dart';

/// DEPRECATED: Use DevicesScreen instead
class DeviceSetupScreen extends StatelessWidget {
  const DeviceSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DevicesScreen()),
      );
    });
    
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
