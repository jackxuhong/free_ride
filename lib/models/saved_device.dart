import 'package:hive/hive.dart';
import 'package:free_ride/services/device_adapter.dart';

part 'saved_device.g.dart';

@HiveType(typeId: 10)
class SavedDevice extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String bluetoothName;

  @HiveField(2)
  String customName;

  @HiveField(3)
  String address;

  @HiveField(4)
  String adapterType; // 'ftms', 'echelon', 'heartrate'

  @HiveField(5)
  String deviceTypeString; // stored as string for Hive compatibility

  @HiveField(6)
  double powerCalibration;

  @HiveField(7)
  DateTime? lastConnected;

  SavedDevice({
    required this.id,
    required this.bluetoothName,
    required this.customName,
    required this.address,
    required this.adapterType,
    required this.deviceTypeString,
    this.powerCalibration = 1.0,
    this.lastConnected,
  });

  // Helper getter for DeviceType enum
  DeviceType get deviceType {
    switch (deviceTypeString) {
      case 'bike':
        return DeviceType.bike;
      case 'treadmill':
        return DeviceType.treadmill;
      case 'heartRateMonitor':
        return DeviceType.heartRateMonitor;
      default:
        return DeviceType.bike;
    }
  }

  // Helper setter for DeviceType enum
  set deviceType(DeviceType type) {
    switch (type) {
      case DeviceType.bike:
        deviceTypeString = 'bike';
        break;
      case DeviceType.treadmill:
        deviceTypeString = 'treadmill';
        break;
      case DeviceType.heartRateMonitor:
        deviceTypeString = 'heartRateMonitor';
        break;
    }
  }

  // Display name with address suffix for identification
  String get displayName => '$customName (${address.substring(address.length - 4)})';

  // Short address for UI display
  String get shortAddress => address.substring(address.length - 4).toUpperCase();

  SavedDevice copyWith({
    String? id,
    String? bluetoothName,
    String? customName,
    String? address,
    String? adapterType,
    String? deviceTypeString,
    double? powerCalibration,
    DateTime? lastConnected,
  }) {
    return SavedDevice(
      id: id ?? this.id,
      bluetoothName: bluetoothName ?? this.bluetoothName,
      customName: customName ?? this.customName,
      address: address ?? this.address,
      adapterType: adapterType ?? this.adapterType,
      deviceTypeString: deviceTypeString ?? this.deviceTypeString,
      powerCalibration: powerCalibration ?? this.powerCalibration,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }
}
