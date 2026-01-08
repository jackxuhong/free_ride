import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Enum representing the type of workout device
enum DeviceType {
  bike,
  treadmill,
  heartRateMonitor,
}

/// Data class containing metrics from a connected device
class DeviceMetrics {
  final double? cadence;
  final double? speed; // km/h
  final double? distance; // km
  final int? power; // watts
  final int? resistance;
  final int? heartRate; // bpm
  final DateTime timestamp;

  DeviceMetrics({
    this.cadence,
    this.speed,
    this.distance,
    this.power,
    this.resistance,
    this.heartRate,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  DeviceMetrics copyWith({
    double? cadence,
    double? speed,
    double? distance,
    int? power,
    int? resistance,
    int? heartRate,
    DateTime? timestamp,
  }) {
    return DeviceMetrics(
      cadence: cadence ?? this.cadence,
      speed: speed ?? this.speed,
      distance: distance ?? this.distance,
      power: power ?? this.power,
      resistance: resistance ?? this.resistance,
      heartRate: heartRate ?? this.heartRate,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Abstract adapter interface for all device types
/// Implementations: FTMSAdapter, EchelonAdapter, HeartRateAdapter
abstract class DeviceAdapter {
  /// The type of device this adapter handles
  DeviceType get deviceType;

  /// Current connection state
  bool get isConnected;

  /// Stream of connection state changes (true = connected, false = disconnected)
  Stream<bool> get connectionStateStream;

  /// Stream of device metrics updates
  Stream<DeviceMetrics> get metricsStream;

  /// Power calibration multiplier (default 1.0)
  double get powerCalibration;
  set powerCalibration(double value);

  /// Connect to the device
  /// For virtual devices, parameter is ignored
  /// For real devices, deviceInfo contains the BluetoothDevice address to connect to
  /// Returns true if connection successful, false otherwise
  Future<bool> connect(dynamic deviceInfo);

  /// Disconnect from the current device
  Future<void> disconnect();

  /// Set resistance level (bike/treadmill only, ignored by HR monitors)
  /// Level range depends on device type (typically 1-32 for Echelon, 0-100 for FTMS)
  Future<void> setResistance(int level);

  /// Dispose of resources and clean up subscriptions
  void dispose();
}
