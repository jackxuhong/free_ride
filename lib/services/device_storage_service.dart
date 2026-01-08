import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/models/saved_device.dart';

class DeviceStorageService {
  static final DeviceStorageService _instance = DeviceStorageService._internal();
  factory DeviceStorageService() => _instance;
  DeviceStorageService._internal();

  static const String _boxName = 'saved_devices';
  static const String _lastUsedKey = 'last_used_device_id';
  
  late Box<SavedDevice> _devicesBox;
  late Box<dynamic> _settingsBox;
  bool _initialized = false;

  /// Initialize the service
  Future<void> init(Box<dynamic> settingsBox) async {
    if (_initialized) return;

    _settingsBox = settingsBox;
    
    // Register Hive adapter for SavedDevice
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(SavedDeviceAdapter());
    }
    
    // Open devices box
    _devicesBox = await Hive.openBox<SavedDevice>(_boxName);

    _initialized = true;
  }

  /// Get all saved devices
  List<SavedDevice> getAllDevices() {
    return _devicesBox.values.toList();
  }

  /// Get devices filtered by adapter type
  List<SavedDevice> getDevicesByAdapterType(String adapterType) {
    return _devicesBox.values
        .where((device) => device.adapterType == adapterType)
        .toList();
  }

  /// Get device by ID
  SavedDevice? getDevice(String id) {
    return _devicesBox.get(id);
  }

  /// Save or update a device
  Future<void> saveDevice(SavedDevice device) async {
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

  /// Check if a device with the given address already exists
  bool deviceExists(String address) {
    return _devicesBox.values.any((device) => device.address == address);
  }

  /// Get device by Bluetooth address
  SavedDevice? getDeviceByAddress(String address) {
    try {
      return _devicesBox.values.firstWhere((device) => device.address == address);
    } catch (e) {
      return null;
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
  SavedDevice? getLastUsedDevice() {
    final lastUsedId = getLastUsedDeviceId();
    if (lastUsedId == null) return null;
    return getDevice(lastUsedId);
  }

  /// Update device last connected time
  Future<void> updateLastConnected(String deviceId) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    device.lastConnected = DateTime.now();
    await saveDevice(device);
  }

  /// Update power calibration for a device
  Future<void> updatePowerCalibration(String deviceId, double calibration) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    device.powerCalibration = calibration;
    await saveDevice(device);
  }

  /// Update custom name for a device
  Future<void> updateCustomName(String deviceId, String customName) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    device.customName = customName;
    await saveDevice(device);
  }

  /// Clear all saved devices
  Future<void> clearAll() async {
    await _devicesBox.clear();
  }
}
