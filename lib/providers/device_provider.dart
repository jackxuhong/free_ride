import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive/hive.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/services/saved_device_storage_service.dart';
import 'package:free_ride/services/device_factory.dart';
import 'package:free_ride/services/device_adapter.dart';

class DeviceProvider extends ChangeNotifier {
  final SavedDeviceStorageService _storage = SavedDeviceStorageService();

  SavedDevice? _selectedDevice;
  DeviceAdapter? _activeDevice;
  bool _isScanning = false;
  List<SavedDevice> _availableDevices = [];

  SavedDevice? get selectedDevice => _selectedDevice;
  DeviceAdapter? get activeDevice => _activeDevice;
  bool get isScanning => _isScanning;
  List<SavedDevice> get availableDevices => _availableDevices;
  bool get hasDeviceSelected => _selectedDevice != null;

  /// Initialize provider and load last used device
  Future<void> init() async {
    // Initialize storage service with settings box
    final settingsBox = await Hive.openBox('app_settings');
    await _storage.init(settingsBox);
    
    await _loadDevices();
    await _loadLastUsedDevice();
  }

  /// Load all saved devices
  Future<void> _loadDevices() async {
    _availableDevices = _storage.getAllDevices();
    notifyListeners();
  }

  /// Load and auto-select last used device
  Future<void> _loadLastUsedDevice() async {
    final lastUsed = _storage.getLastUsedDevice();
    if (lastUsed != null) {
      await selectDevice(lastUsed);
    }
  }

  /// Select a device
  Future<void> selectDevice(SavedDevice device) async {
    // Dispose old active device if it exists
    if (_activeDevice != null && _selectedDevice?.id != device.id) {
      _activeDevice?.dispose();
      _activeDevice = null;
    }

    _selectedDevice = device;
    await _storage.setLastUsedDeviceId(device.id);

    // Create adapter from device
    _activeDevice = DeviceFactory.createAdapter(device);

    // Apply any stored configurations
    if (device.configurations.isNotEmpty) {
      _activeDevice?.applyConfiguration(device.configurations);
    }

    // Apply power calibration
    _activeDevice?.powerCalibration = device.powerCalibration;

    notifyListeners();
  }

  /// Delete a device
  Future<void> deleteDevice(String deviceId) async {
    // Don't allow removing virtual devices
    final device = _storage.getDevice(deviceId);
    if (device?.adapterType == 'virtual-bike' || device?.adapterType == 'virtual-treadmill') {
      throw Exception('Cannot remove virtual devices');
    }

    await _storage.deleteDevice(deviceId);

    // If deleted device was selected, clear selection
    if (_selectedDevice?.id == deviceId) {
      _selectedDevice = null;
      _activeDevice?.dispose();
      _activeDevice = null;
    }

    await _loadDevices();
  }

  /// Remove a device (alias for deleteDevice)
  Future<void> removeDevice(String deviceId) async {
    await deleteDevice(deviceId);
  }

  /// Update device configurations
  Future<void> updateConfigurations(String deviceId, Map<String, dynamic> configs) async {
    await _storage.updateConfigurations(deviceId, configs);
    
    // Reload and update selected device if needed
    await _loadDevices();
    if (_selectedDevice?.id == deviceId) {
      final updated = _storage.getDevice(deviceId);
      if (updated != null) {
        _selectedDevice = updated;
        _activeDevice?.applyConfiguration(configs);
        notifyListeners();
      }
    }
  }

  /// Update virtual device parameters (alias for updateConfigurations)
  Future<void> updateDeviceParameters({
    required String deviceId,
    double? effortLevel,
    double? controllableParam,
  }) async {
    final configs = <String, dynamic>{};
    if (effortLevel != null) configs['effortLevel'] = effortLevel;
    if (controllableParam != null) configs['controllableParam'] = controllableParam;
    
    await updateConfigurations(deviceId, configs);
  }

  /// Start scanning for real devices
  Future<void> startScan() async {
    if (_isScanning) return;

    _isScanning = true;
    notifyListeners();

    try {
      await DeviceFactory.startDiscovery(
        onDeviceFound: (BluetoothDevice device, String adapterType, DeviceType deviceType) async {
          // Check if already saved
          final existing = _availableDevices.firstWhere(
            (d) => d.address == device.remoteId.toString(),
            orElse: () => SavedDevice(
              id: '',
              bluetoothName: '',
              customName: '',
              address: '',
              adapterType: '',
              deviceTypeString: '',
            ),
          );

          if (existing.id.isEmpty) {
            final newDevice = SavedDevice(
              id: device.remoteId.toString(),
              bluetoothName: device.platformName,
              customName: device.platformName.isNotEmpty ? device.platformName : 'Device',
              address: device.remoteId.toString(),
              adapterType: adapterType,
              deviceTypeString: deviceType == DeviceType.bike ? 'bike' : 'treadmill',
              powerCalibration: 1.0,
              configurations: {},
            );
            await _storage.saveDevice(newDevice);
            _availableDevices.add(newDevice);
            notifyListeners();
          }
        },
      );
    } catch (e) {
      debugPrint('Error scanning: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    await DeviceFactory.stopDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  /// Refresh devices list
  Future<void> refreshDevices() async {
    await _loadDevices();
  }

  @override
  void dispose() {
    _activeDevice?.dispose();
    super.dispose();
  }
}
