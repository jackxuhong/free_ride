/// Snapshot of device data at a point in time
class DeviceDataSnapshot {
  /// Current speed in km/h
  final double? speed;

  /// Current power output in watts
  final double? power;

  /// For bikes: cadence in RPM
  /// For treadmills: pace in min/km
  final double? cadenceOrPace;

  /// Heart rate in bpm
  final int? heartRate;

  /// Current controllable parameter value
  /// For bikes: resistance level (1-20)
  /// For treadmills: incline percentage (-3 to 15)
  final double? controllableParam;

  /// Timestamp of this snapshot
  final DateTime timestamp;

  DeviceDataSnapshot({
    this.speed,
    this.power,
    this.cadenceOrPace,
    this.heartRate,
    this.controllableParam,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Copy with method for updates
  DeviceDataSnapshot copyWith({
    double? speed,
    double? power,
    double? cadenceOrPace,
    int? heartRate,
    double? controllableParam,
    DateTime? timestamp,
  }) {
    return DeviceDataSnapshot(
      speed: speed ?? this.speed,
      power: power ?? this.power,
      cadenceOrPace: cadenceOrPace ?? this.cadenceOrPace,
      heartRate: heartRate ?? this.heartRate,
      controllableParam: controllableParam ?? this.controllableParam,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'DeviceDataSnapshot('
        'speed: ${speed?.toStringAsFixed(1)} km/h, '
        'power: ${power?.toStringAsFixed(0)}W, '
        'cadence/pace: ${cadenceOrPace?.toStringAsFixed(1)}, '
        'HR: $heartRate bpm, '
        'param: ${controllableParam?.toStringAsFixed(1)}'
        ')';
  }
}
