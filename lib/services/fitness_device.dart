import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// Unified interface for all fitness devices (real FTMS and virtual)
abstract class FitnessDevice {
  DeviceType get deviceType;

  // Connection state (for real devices, always true for virtual)
  bool get isConnected;
  Stream<bool> get connectionState;

  // Device capabilities (useful for UI)
  int get minResistance;
  int get maxResistance;
  double get minIncline;
  double get maxIncline;

  // Update device input parameters
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  });

  // Simulate device physics and return current state
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  });

  // Send control command to device
  Future<bool> sendControlCommand(ControlCommand command);

  // Get FTMS data packet (for virtual devices to simulate real protocol)
  Uint8List getFTMSDataPacket();

  // Dispose resources
  void dispose();
}
