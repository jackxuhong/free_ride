import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// Handles sending control commands to FTMS devices
class FTMSCommandSender {
  final BluetoothCharacteristic? controlCharacteristic;
  final int minResistance;
  final int maxResistance;

  FTMSCommandSender({
    required this.controlCharacteristic,
    required this.minResistance,
    required this.maxResistance,
  });

  /// Send a control command to the device
  Future<bool> sendControlCommand(ControlCommand command) async {
    try {
      if (controlCharacteristic == null) {
        // print('Control characteristic not available');
        return false;
      }

      // Build command packet based on command type
      List<int> packet;
      switch (command) {
        case SetResistance(level: final level):
          // For bikes with simulation support, use simulation parameters instead
          // Opcode 0x11: Set Indoor Bike Simulation Parameters
          // Calculate grade from resistance level
          final gradePercent = ((level - minResistance - (maxResistance - minResistance) * 0.25) * 20.0 / (maxResistance - minResistance)).clamp(-5.0, 15.0);
          final windSpeed = 0; // 0 m/s
          final grade = (gradePercent * 100).round(); // Convert to 0.01% resolution
          final crr = 40; // 0.004 (typical rolling resistance)
          final windResistance = 40; // 0.4 kg/m (typical)

          packet = [
            0x11, // Opcode: Set Indoor Bike Simulation Parameters
            windSpeed & 0xFF, (windSpeed >> 8) & 0xFF, // Wind speed (sint16, 0.001 m/s resolution)
            grade & 0xFF, (grade >> 8) & 0xFF, // Grade (sint16, 0.01% resolution)
            crr, // Coefficient of rolling resistance (uint8, 0.0001 resolution)
            windResistance, // Wind resistance coefficient (uint8, 0.01 kg/m resolution)
          ];
        case SetIncline(percentage: final percentage):
          // Opcode 0x06: Set Target Inclination
          final inclineValue = (percentage * 10).round(); // Resolution 0.1%
          packet = [
            0x06,
            inclineValue & 0xFF,
            (inclineValue >> 8) & 0xFF,
          ];
      }

      await controlCharacteristic!.write(packet, withoutResponse: false);
      return true;
    } catch (e) {
      print('Error sending control command: $e');
      return false;
    }
  }
}