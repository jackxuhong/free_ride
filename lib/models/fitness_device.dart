import 'package:hive/hive.dart';

part 'fitness_device.g.dart';

/// Device types supported by the app
@HiveType(typeId: 9)
enum DeviceType {
  @HiveField(0)
  indoorBike,
  @HiveField(1)
  treadmill,
}

@HiveType(typeId: 8)
class FitnessDevice extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DeviceType deviceType;

  @HiveField(3)
  bool isVirtual;

  @HiveField(4)
  String? deviceAddress;

  @HiveField(5)
  DateTime? lastConnected;

  @HiveField(6)
  double effortLevel; // For virtual devices: 0-100% effort, or speed for treadmills

  @HiveField(7)
  double controllableParam; // For bikes: resistance (1-20), for treadmills: incline (-3 to 15)

  FitnessDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.isVirtual,
    this.deviceAddress,
    this.lastConnected,
    this.effortLevel = 50.0,
    this.controllableParam = 10.0,
  });

  /// Display name with type indicator
  String get displayName => isVirtual ? '$name (Virtual)' : name;

  /// Copy method for updates
  FitnessDevice copyWith({
    String? id,
    String? name,
    DeviceType? deviceType,
    bool? isVirtual,
    String? deviceAddress,
    DateTime? lastConnected,
    double? effortLevel,
    double? controllableParam,
  }) {
    return FitnessDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceType: deviceType ?? this.deviceType,
      isVirtual: isVirtual ?? this.isVirtual,
      deviceAddress: deviceAddress ?? this.deviceAddress,
      lastConnected: lastConnected ?? this.lastConnected,
      effortLevel: effortLevel ?? this.effortLevel,
      controllableParam: controllableParam ?? this.controllableParam,
    );
  }

  @override
  String toString() {
    return 'FitnessDevice(id: $id, name: $name, type: $deviceType, virtual: $isVirtual)';
  }
}