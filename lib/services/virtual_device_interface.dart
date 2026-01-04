import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';

/// Abstract base class for all fitness devices (virtual and real FTMS)
abstract class VirtualFitnessDevice {
  /// Device type
  DeviceType get deviceType;

  /// Update device input parameters
  /// For bikes: effortLevel = user effort (0-100%), controllableParam = resistance
  /// For treadmills: effortLevel = user speed (km/h), controllableParam = incline
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  });

  /// Simulate device physics and return current state
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  });

  /// Send control command to device
  Future<bool> sendControlCommand(ControlCommand command);

  /// Get FTMS data packet (for virtual devices to simulate real protocol)
  Uint8List getFTMSDataPacket();

  /// Dispose resources
  void dispose() {}
}

/// Base class for control commands
sealed class ControlCommand {
  const ControlCommand();
}

/// Set resistance level (for bikes)
class SetResistance extends ControlCommand {
  final int level; // 1-20

  const SetResistance(this.level);

  @override
  String toString() => 'SetResistance($level)';
}

/// Set incline percentage (for treadmills)
class SetIncline extends ControlCommand {
  final double percentage; // -3.0 to +15.0

  const SetIncline(this.percentage);

  @override
  String toString() => 'SetIncline(${percentage.toStringAsFixed(1)}%)';
}
