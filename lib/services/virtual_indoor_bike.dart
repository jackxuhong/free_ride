import 'dart:math';
import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/heart_rate_simulator.dart';

/// Virtual indoor bike simulator
class VirtualIndoorBike extends VirtualFitnessDevice {
  double _effortLevel = 50.0; // 0-100%
  double _resistanceLevel = 10.0; // 1-20
  double _currentSpeed = 0.0;
  double _currentPower = 0.0;
  double _currentCadence = 0.0;
  
  final HeartRateSimulator _hrSimulator;

  VirtualIndoorBike({
    double effortLevel = 50.0,
    double resistanceLevel = 10.0,
    HeartRateSimulator? hrSimulator,
  })  : _effortLevel = effortLevel,
        _resistanceLevel = resistanceLevel,
        _hrSimulator = hrSimulator ?? HeartRateSimulator();

  @override
  DeviceType get deviceType => DeviceType.indoorBike;

  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    _effortLevel = effortLevel.clamp(0, 100);
    _resistanceLevel = controllableParam.clamp(1, 20);
  }

  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // If following a route, adjust resistance based on grade
    if (routeGrade != null) {
      // Map grade to resistance: grade/0.8 + 10
      // -7.2% → resistance 1, 0% → resistance 10, 8% → resistance 20
      final targetResistance = (routeGrade / 0.8 + 10).clamp(1.0, 20.0);
      _resistanceLevel = targetResistance;
    }

    // Calculate speed with intensity multiplier
    _currentSpeed = _calculateSpeed(_effortLevel, _resistanceLevel, intensityMultiplier);

    // Calculate power with intensity multiplier
    _currentPower = _calculatePower(_effortLevel, _resistanceLevel, intensityMultiplier);

    // Calculate cadence (not affected by intensity, it's a mechanical output)
    _currentCadence = _calculateCadence(_effortLevel, _resistanceLevel);

    // Update heart rate with intensity
    final hr = _hrSimulator.updateHeartRate(
      effortLevel: _effortLevel,
      deltaTime: deltaTime,
      intensityMultiplier: intensityMultiplier,
    );

    return DeviceDataSnapshot(
      speed: _currentSpeed,
      power: _currentPower,
      cadenceOrPace: _currentCadence,
      heartRate: hr.round(),
      controllableParam: _resistanceLevel,
    );
  }

  /// Calculate speed from effort and resistance with intensity
  /// Formula: speed = 20 × (0.3 + effort/100 × 1.7) × (1.0 - (resistance-10) × 0.04) × intensity
  double _calculateSpeed(double effort, double resistance, double intensity) {
    const baseSpeed = 20.0; // km/h
    final effortMultiplier = 0.3 + (effort / 100.0) * 1.7;
    final resistanceMultiplier = 1.0 - (resistance - 10.0) * 0.04;
    return baseSpeed * effortMultiplier * resistanceMultiplier * intensity;
  }

  /// Calculate power from effort and resistance with intensity
  /// Formula: power = min(400, 50 + 250 × (effort/100)^1.2 × (1 + (resistance-1) × 0.15)) × intensity
  double _calculatePower(double effort, double resistance, double intensity) {
    const basePower = 50.0; // watts
    const maxPower = 400.0; // watts (realistic for average rider)
    
    final effortFactor = pow(effort / 100.0, 1.2);
    final resistanceFactor = 1.0 + (resistance - 1.0) * 0.15;
    
    final power = basePower + 250.0 * effortFactor * resistanceFactor;
    return min(maxPower, power) * intensity;
  }

  /// Calculate cadence from effort and resistance
  /// Formula: cadence = clamp(40 × (1 + effort/100 × 1.5) × (1 - (resistance-1) × 0.015), 0, 120)
  double _calculateCadence(double effort, double resistance) {
    const baseCadence = 40.0; // RPM
    const maxCadence = 120.0; // RPM
    
    final effortFactor = 1.0 + (effort / 100.0) * 1.5;
    final resistancePenalty = 1.0 - (resistance - 1.0) * 0.015;
    
    final cadence = baseCadence * effortFactor * resistancePenalty;
    return cadence.clamp(0, maxCadence);
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
