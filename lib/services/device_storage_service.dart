import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:uuid/uuid.dart';

class DeviceStorageService {
  static final DeviceStorageService _instance = DeviceStorageService._internal();
  factory DeviceStorageService() => _instance;
  DeviceStorageService._internal();

  static const String _boxName = 'ftms_devices';
  static const String _lastUsedKey = 'last_used_device_id';
  
  late Box<FTMSDevice> _devicesBox;
  late Box<dynamic> _settingsBox;
  bool _initialized = false;

  /// Initialize the service and create default virtual devices
  Future<void> init(Box<dynamic> settingsBox) async {
    if (_initialized) return;

    _settingsBox = settingsBox;
    
    // Register Hive adapters
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(FTMSDeviceAdapter());
    }
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(DeviceTypeAdapter());
    }
    
    // Open devices box
    _devicesBox = await Hive.openBox<FTMSDevice>(_boxName);

    // Create default virtual devices if this is first launch
    if (_devicesBox.isEmpty) {
      await _createDefaultVirtualDevices();
    }

    _initialized = true;
  }

  /// Create two default virtual devices for testing
  Future<void> _createDefaultVirtualDevices() async {
    final uuid = const Uuid();

    // Virtual Bike
    final virtualBike = FTMSDevice(
      id: uuid.v4(),
      name: 'Virtual Bike',
      deviceType: DeviceType.indoorBike,
      isVirtual: true,
      effortLevel: 25.0, // 25 km/h speed
      controllableParam: 0.0, // Unused (route controls resistance)
    );

    // Virtual Treadmill
    final virtualTreadmill = FTMSDevice(
      id: uuid.v4(),
      name: 'Virtual Treadmill',
      deviceType: DeviceType.treadmill,
      isVirtual: true,
      effortLevel: 10.0, // 10 km/h speed
      controllableParam: 0.0, // Unused (route controls incline)
    );

    await _devicesBox.put(virtualBike.id, virtualBike);
    await _devicesBox.put(virtualTreadmill.id, virtualTreadmill);
  }

  /// Get all saved devices
  List<FTMSDevice> getAllDevices() {
    return _devicesBox.values.toList();
  }

  /// Get device by ID
  FTMSDevice? getDevice(String id) {
    return _devicesBox.get(id);
  }

  /// Save or update a device
  Future<void> saveDevice(FTMSDevice device) async {
    await _devicesBox.put(device.id, device);
  }

  /// Delete a device
  Future<void> deleteDevice(String id) async {
    await _devicesBox.delete(id);
    
    // Clear last used if this was the last used device
    if (getLastUsedDeviceId() == id) {
      await clearLastUsedDevice();
    }
  }

  /// Get last used device ID
  String? getLastUsedDeviceId() {
    return _settingsBox.get(_lastUsedKey);
  }

  /// Set last used device ID
  Future<void> setLastUsedDeviceId(String deviceId) async {
    await _settingsBox.put(_lastUsedKey, deviceId);
  }

  /// Clear last used device
  Future<void> clearLastUsedDevice() async {
    await _settingsBox.delete(_lastUsedKey);
  }

  /// Get last used device
  FTMSDevice? getLastUsedDevice() {
    final lastUsedId = getLastUsedDeviceId();
    if (lastUsedId == null) return null;
    return getDevice(lastUsedId);
  }

  /// Update device parameters (effort and controllable param)
  Future<void> updateDeviceParameters(
    String deviceId, {
    double? effortLevel,
    double? controllableParam,
  }) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(
      effortLevel: effortLevel ?? device.effortLevel,
      controllableParam: controllableParam ?? device.controllableParam,
    );

    await saveDevice(updated);
  }

  /// Update device last connected time
  Future<void> updateLastConnected(String deviceId) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(lastConnected: DateTime.now());
    await saveDevice(updated);
  }
}
