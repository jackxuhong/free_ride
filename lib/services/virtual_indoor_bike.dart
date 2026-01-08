import 'dart:math';
import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/heart_rate_simulator.dart';

/// Virtual indoor bike simulator
class VirtualIndoorBike extends VirtualFitnessDevice {
  double _targetSpeed = 25.0; // Target speed in km/h
  double _resistanceLevel = 10.0; // 1-20
  double _currentSpeed = 0.0;
  double _currentPower = 0.0;
  double _currentCadence = 0.0;
  
  final HeartRateSimulator _hrSimulator;

  VirtualIndoorBike({
    double targetSpeed = 25.0,
    double resistanceLevel = 10.0,
    HeartRateSimulator? hrSimulator,
  })  : _targetSpeed = targetSpeed,
        _resistanceLevel = resistanceLevel,
        _hrSimulator = hrSimulator ?? HeartRateSimulator();

  @override
  DeviceType get deviceType => DeviceType.indoorBike;

  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    // effortLevel is now target speed (km/h)
    _targetSpeed = effortLevel.clamp(0, 200);
  }

  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // If following a route, adjust resistance based on grade
    double baseResistance = _resistanceLevel;
    if (routeGrade != null) {
      // Map grade to resistance: grade/0.8 + 10
      // -7.2% → resistance 1, 0% → resistance 10, 8% → resistance 20
      baseResistance = (routeGrade / 0.8 + 10).clamp(1.0, 20.0);
    }

    // Apply intensity multiplier to resistance (makes workout harder/easier)
    final effectiveResistance = (baseResistance * intensityMultiplier).clamp(1.0, 20.0);

    // Use target speed as current speed (user controls speed directly)
    _currentSpeed = _targetSpeed;

    // Calculate power based on speed and effective resistance
    _currentPower = _calculatePowerFromSpeed(_targetSpeed, effectiveResistance);

    // Calculate cadence based on speed and resistance
    _currentCadence = _calculateCadenceFromSpeed(_targetSpeed, effectiveResistance);

    // Calculate effort level for HR from speed and resistance
    final effortFromSpeed = (_targetSpeed / 40.0 * 100).clamp(0.0, 100.0); // 40 km/h = 100% effort
    final effectiveEffort = (effortFromSpeed * (1.0 + (effectiveResistance - 10) / 20)).clamp(0.0, 100.0);
    final hr = _hrSimulator.updateHeartRate(
      effortLevel: effectiveEffort,
      deltaTime: deltaTime,
      intensityMultiplier: 1.0,
    );

    return DeviceDataSnapshot(
      speed: _currentSpeed,
      power: _currentPower,
      cadenceOrPace: _currentCadence,
      heartRate: hr.round(),
      controllableParam: effectiveResistance,
    );
  }

  /// Calculate power from speed and resistance
  /// Power increases with both speed and resistance
  double _calculatePowerFromSpeed(double speedKmh, double resistance) {
    // Base power proportional to speed
    final speedFactor = speedKmh / 25.0; // Normalized to 25 km/h
    // Resistance multiplier (resistance 10 = 1.0×, 20 = 2.35×)
    final resistanceFactor = 1.0 + (resistance - 1) * 0.15;
    final basePower = 100 * speedFactor * resistanceFactor;
    return min(400.0, basePower);
  }

  /// Calculate cadence from speed and resistance
  /// Higher speed = higher cadence, higher resistance = lower cadence
  double _calculateCadenceFromSpeed(double speedKmh, double resistance) {
    // Base cadence from speed: 25 km/h ≈ 80 RPM
    final baseCadence = (speedKmh / 25.0) * 80.0;
    // Resistance reduces cadence slightly (harder to pedal fast)
    final resistanceFactor = 1.0 - (resistance - 1) * 0.015;
    return (baseCadence * resistanceFactor).clamp(0, 120);
  }

  @override
  Future<bool> sendControlCommand(ControlCommand command) async {
    if (command is SetResistance) {
      _resistanceLevel = command.level.toDouble().clamp(1, 20);
      return true;
    }
    return false;
  }

  @override
  Uint8List getFTMSDataPacket() {
    // Simulate FTMS Indoor Bike Data packet (UUID 0x2AD2)
    // This is a simplified version for testing
    final builder = ByteData(16);
    
    // Flags (bytes 0-1): Speed, Cadence, Power, Resistance, HR present
    builder.setUint16(0, 0x02E4, Endian.little);
    
    // Speed (bytes 2-3): UINT16, resolution 0.01 km/h
    builder.setUint16(2, (_currentSpeed * 100).round(), Endian.little);
    
    // Cadence (bytes 4-5): UINT16, resolution 0.5 RPM
    builder.setUint16(4, (_currentCadence * 2).round(), Endian.little);
    
    // Power (bytes 6-7): SINT16, resolution 1 W
    builder.setInt16(6, _currentPower.round(), Endian.little);
    
    // Resistance (bytes 8-9): UINT16
    builder.setUint16(8, _resistanceLevel.round(), Endian.little);
    
    // Heart Rate (byte 10): UINT8
    builder.setUint8(10, _hrSimulator.currentHR.round());
    
    return builder.buffer.asUint8List();
  }

  @override
  void dispose() {
    // Nothing to dispose for virtual device
  }
}
