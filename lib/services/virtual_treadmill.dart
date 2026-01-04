import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/heart_rate_simulator.dart';

/// Virtual treadmill simulator
class VirtualTreadmill extends VirtualFitnessDevice {
  double _userSpeed = 10.0; // km/h - user controls this
  double _targetIncline = 0.0; // target incline from route
  double _currentIncline = 0.0; // actual incline (smoothed)
  double _userWeight = 70.0; // kg - for power calculation
  
  final HeartRateSimulator _hrSimulator;

  VirtualTreadmill({
    double userSpeed = 10.0,
    double initialIncline = 0.0,
    double userWeight = 70.0,
    HeartRateSimulator? hrSimulator,
  })  : _userSpeed = userSpeed,
        _targetIncline = initialIncline,
        _currentIncline = initialIncline,
        _userWeight = userWeight,
        _hrSimulator = hrSimulator ?? HeartRateSimulator();

  @override
  DeviceType get deviceType => DeviceType.treadmill;

  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    // For treadmills:
    // effortLevel = user speed (km/h)
    // controllableParam = incline (%)
    _userSpeed = effortLevel.clamp(0, 25);
    _targetIncline = controllableParam.clamp(-3, 15);
  }

  /// Set user weight for power calculation
  void setUserWeight(double weight) {
    _userWeight = weight;
  }

  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // If following a route, set target incline to match grade
    double baseIncline = _targetIncline;
    if (routeGrade != null) {
      // Convert grade (decimal) to incline percentage
      baseIncline = (routeGrade * 100).clamp(-3.0, 15.0);
    }

    // Apply intensity multiplier to incline (not to output metrics)
    _targetIncline = (baseIncline * intensityMultiplier).clamp(-3.0, 15.0);

    // Smooth incline changes (rate limiting: 2% per second max)
    _currentIncline = _smoothIncline(_currentIncline, _targetIncline, deltaTime);

    // Calculate power with intensity-modified incline (convert incline back to decimal grade)
    final power = _calculateRunningPower(_userSpeed, _currentIncline / 100, 1.0);

    // Calculate pace (min/km)
    final pace = _userSpeed > 0 ? 60.0 / _userSpeed : 0.0;

    // Estimate effort from speed and incline for HR calculation
    final estimatedEffort = _estimateEffortFromSpeed(_userSpeed, _currentIncline);

    // Update heart rate based on effort (higher incline = more effort)
    final hr = _hrSimulator.updateHeartRate(
      effortLevel: estimatedEffort,
      deltaTime: deltaTime,
      intensityMultiplier: 1.0,
    );

    return DeviceDataSnapshot(
      speed: _userSpeed,
      power: power,
      cadenceOrPace: pace,
      heartRate: hr.round(),
      controllableParam: _currentIncline,
    );
  }

  /// Smooth incline changes with rate limiting
  /// Max change rate: 2% per second
  double _smoothIncline(double current, double target, double deltaTime) {
    const maxChangePerSecond = 2.0; // 2% per second
    final maxChange = maxChangePerSecond * deltaTime;
    final delta = target - current;

    if (delta.abs() <= maxChange) {
      return target;
    }
    return current + (delta.sign * maxChange);
  }

  /// Calculate running power with intensity
  /// Formula: power = weight(kg) × speed(m/s) × (2.0 + 2.5 × grade) × intensity
  double _calculateRunningPower(double speedKmh, double incline, double intensity) {
    final speedMs = speedKmh / 3.6; // Convert to m/s
    final grade = incline / 100.0; // Convert percentage to decimal
    
    // Running power formula
    final power = _userWeight * speedMs * (2.0 + 2.5 * grade);
    return power * intensity;
  }

  /// Estimate effort level from speed and incline
  /// This is used for heart rate calculation
  double _estimateEffortFromSpeed(double speedKmh, double incline) {
    // Base effort from speed: 0 km/h = 0%, 20 km/h = 80%
    final speedEffort = (speedKmh / 20.0) * 80.0;
    
    // Incline adds to effort: each 5% incline adds ~20% effort
    final inclineEffort = (incline / 5.0) * 20.0;
    
    return (speedEffort + inclineEffort).clamp(0, 100);
  }

  @override
  Future<bool> sendControlCommand(ControlCommand command) async {
    if (command is SetIncline) {
      _targetIncline = command.percentage.clamp(-3, 15);
      return true;
    }
    return false;
  }

  @override
  Uint8List getFTMSDataPacket() {
    // Simulate FTMS Treadmill Data packet (UUID 0x2ACD)
    final builder = ByteData(12);
    
    // Flags (bytes 0-1): Speed, Incline, Pace, HR present
    builder.setUint16(0, 0x018C, Endian.little);
    
    // Speed (bytes 2-3): UINT16, resolution 0.01 km/h
    builder.setUint16(2, (_userSpeed * 100).round(), Endian.little);
    
    // Pace (byte 4): UINT8, min/km
    final pace = _userSpeed > 0 ? (60.0 / _userSpeed).round() : 0;
    builder.setUint8(4, pace);
    
    // Incline (bytes 5-6): SINT16, resolution 0.1%
    builder.setInt16(5, (_currentIncline * 10).round(), Endian.little);
    
    // Heart Rate (byte 7): UINT8
    builder.setUint8(7, _hrSimulator.currentHR.round());
    
    return builder.buffer.asUint8List();
  }

  @override
  void dispose() {
    // Nothing to dispose for virtual device
  }
}
