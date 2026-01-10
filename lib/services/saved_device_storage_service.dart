import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:uuid/uuid.dart';

class SavedDeviceStorageService {
  static final SavedDeviceStorageService _instance =
      SavedDeviceStorageService._internal();

  factory SavedDeviceStorageService() => _instance;
  SavedDeviceStorageService._internal();

  static const String _boxName = 'saved_devices';
  static const String _lastUsedKey = 'last_used_device_id';

  late Box<SavedDevice> _devicesBox;
  late Box<dynamic> _settingsBox;
  bool _initialized = false;

  /// Initialize the service and create default virtual devices
  Future<void> init(Box<dynamic> settingsBox) async {
    if (_initialized) return;

    _settingsBox = settingsBox;

    // Register SavedDevice adapter if not already registered
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(SavedDeviceAdapter());
    }

    try {
      // Open devices box with retry logic
      _devicesBox = await _openBoxWithRetry<SavedDevice>(_boxName);
    } catch (e) {
      // If there's an error opening the box (e.g., incompatible typeId),
      // delete it and create a fresh one
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _devicesBox = await Hive.openBox<SavedDevice>(_boxName);
      } catch (deleteError) {
        rethrow;
      }
    }

    // Ensure default virtual devices always exist
    await _ensureDefaultVirtualDevices();

    _initialized = true;
  }

  /// Open a Hive box with retry logic to handle lock contention
  static Future<Box<T>> _openBoxWithRetry<T>(String boxName, {int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await Hive.openBox<T>(boxName);
      } catch (e) {
        if (i < maxRetries - 1) {
          // Wait before retrying
          await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        } else {
          rethrow;
        }
      }
    }
    throw Exception('Failed to open box: $boxName');
  }

  /// Ensure virtual devices always exist in the storage
  Future<void> _ensureDefaultVirtualDevices() async {
    const uuid = Uuid();

    // Check if virtual bike exists
    final virtualBikeExists = _devicesBox.values.any((d) => d.adapterType == 'virtual-bike');
    if (!virtualBikeExists) {
      final virtualBike = SavedDevice(
        id: uuid.v4(),
        bluetoothName: 'Virtual Bike',
        customName: 'Virtual Bike',
        address: 'virtual-bike',
        adapterType: 'virtual-bike',
        deviceTypeString: 'bike',
        powerCalibration: 1.0,
        configurations: {
          'targetSpeed': 25.0,
          'powerCoefficient': 1.0,
          'minResistance': 1,
          'maxResistance': 32,
        },
      );
      await _devicesBox.put(virtualBike.id, virtualBike);
    }

    // Check if virtual treadmill exists
    final virtualTreadmillExists = _devicesBox.values.any((d) => d.adapterType == 'virtual-treadmill');
    if (!virtualTreadmillExists) {
      final virtualTreadmill = SavedDevice(
        id: uuid.v4(),
        bluetoothName: 'Virtual Treadmill',
        customName: 'Virtual Treadmill',
        address: 'virtual-treadmill',
        adapterType: 'virtual-treadmill',
        deviceTypeString: 'treadmill',
        powerCalibration: 1.0,
        configurations: {
          'targetSpeed': 10.0,
          'powerCoefficient': 1.0,
          'minIncline': -5.0,
          'maxIncline': 15.0,
        },
      );
      await _devicesBox.put(virtualTreadmill.id, virtualTreadmill);
    }
  }

  /// Get all saved devices
  List<SavedDevice> getAllDevices() {
    return _devicesBox.values.toList();
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

  /// Update device configurations
  Future<void> updateConfigurations(
    String deviceId,
    Map<String, dynamic> configs,
  ) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(
      configurations: {...device.configurations, ...configs},
    );
    await saveDevice(updated);
  }

  /// Update power calibration
  Future<void> updatePowerCalibration(String deviceId, double calibration) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(powerCalibration: calibration);
    await saveDevice(updated);
  }

  /// Update custom device name
  Future<void> updateCustomName(String deviceId, String newName) async {
    final device = getDevice(deviceId);
    if (device == null) return;

    final updated = device.copyWith(customName: newName);
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
