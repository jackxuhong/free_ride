import 'package:flutter/foundation.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/services/device_factory.dart';

class DeviceProvider extends ChangeNotifier {
  final DeviceStorageService _storage = DeviceStorageService();

  SavedDevice? _selectedPrimaryDevice;
  SavedDevice? _selectedHRDevice;
  DeviceAdapter? _primaryAdapter;
  DeviceAdapter? _hrAdapter;
  List<SavedDevice> _availableDevices = [];

  SavedDevice? get selectedDevice => _selectedPrimaryDevice;
  SavedDevice? get selectedPrimaryDevice => _selectedPrimaryDevice;
  SavedDevice? get selectedHRDevice => _selectedHRDevice;
  DeviceAdapter? get activeDevice => _primaryAdapter;
  DeviceAdapter? get primaryAdapter => _primaryAdapter;
  DeviceAdapter? get hrAdapter => _hrAdapter;
  List<SavedDevice> get availableDevices => _availableDevices;
  bool get hasDeviceSelected => _selectedPrimaryDevice != null;

  /// Initialize provider and load last used device
  Future<void> init() async {
    await _ensureVirtualDevices();
    await _loadDevices();
    await _loadLastUsedDevice();
  }

  /// Ensure virtual devices always exist
  Future<void> _ensureVirtualDevices() async {
    final devices = _storage.getAllDevices();
    
    // Check if virtual bike exists
    final hasVirtualBike = devices.any((d) => d.adapterType == 'virtual-bike');
    if (!hasVirtualBike) {
      final virtualBike = SavedDevice(
        id: 'virtual-bike-default',
        bluetoothName: 'Virtual Bike',
        customName: 'Virtual Bike',
        address: 'virtual-bike',
        adapterType: 'virtual-bike',
        deviceTypeString: 'bike',
        powerCalibration: 30.0, // Using powerCalibration field to store speed
        lastConnected: DateTime.now(),
      );
      await _storage.saveDevice(virtualBike);
    }
    
    // Check if virtual treadmill exists
    final hasVirtualTreadmill = devices.any((d) => d.adapterType == 'virtual-treadmill');
    if (!hasVirtualTreadmill) {
      final virtualTreadmill = SavedDevice(
        id: 'virtual-treadmill-default',
        bluetoothName: 'Virtual Treadmill',
        customName: 'Virtual Treadmill',
        address: 'virtual-treadmill',
        adapterType: 'virtual-treadmill',
        deviceTypeString: 'treadmill',
        powerCalibration: 15.0, // Using powerCalibration field to store speed
        lastConnected: DateTime.now(),
      );
      await _storage.saveDevice(virtualTreadmill);
    }
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

  /// Select a primary workout device (bike or treadmill)
  Future<void> selectDevice(SavedDevice device) async {
    // Only allow bike/treadmill as primary device
    if (device.deviceType == DeviceType.heartRateMonitor) {
      throw Exception('HR monitors must be selected as secondary devices');
    }

    // Dispose old adapter if it exists
    if (_primaryAdapter != null && _selectedPrimaryDevice?.id != device.id) {
      _primaryAdapter?.dispose();
      _primaryAdapter = null;
    }
    
    _selectedPrimaryDevice = device;
    await _storage.setLastUsedDeviceId(device.id);
    
    // Create adapter (don't connect yet - connection happens on ride start)
    if (_primaryAdapter == null) {
      _primaryAdapter = DeviceFactory.createAdapter(device);
    } else {
      // Update calibration if adapter already exists
      _primaryAdapter!.powerCalibration = device.powerCalibration;
    }
    
    notifyListeners();
  }

  /// Select a heart rate monitor as secondary device
  Future<void> selectHRDevice(SavedDevice? device) async {
    if (device != null && device.deviceType != DeviceType.heartRateMonitor) {
      throw Exception('Only HR monitors can be selected as secondary devices');
    }

    // Dispose old HR adapter if it exists
    if (_hrAdapter != null) {
      _hrAdapter?.dispose();
      _hrAdapter = null;
    }
    
    _selectedHRDevice = device;
    
    // Create HR adapter (don't connect yet)
    if (device != null) {
      _hrAdapter = DeviceFactory.createAdapter(device);
    }
    
    notifyListeners();
  }

  /// Remove a device
  Future<void> removeDevice(String deviceId) async {
    final device = _storage.getDevice(deviceId);
    if (device == null) return;
    
    // Dispose adapter if removing the selected device
    if (_selectedPrimaryDevice?.id == deviceId) {
      _primaryAdapter?.dispose();
      _primaryAdapter = null;
      _selectedPrimaryDevice = null;
    }
    
    if (_selectedHRDevice?.id == deviceId) {
      _hrAdapter?.dispose();
      _hrAdapter = null;
      _selectedHRDevice = null;
    }
    
    await _storage.deleteDevice(deviceId);
    await _loadDevices();
    notifyListeners();
  }

  /// Update power calibration for a device
  Future<void> updatePowerCalibration(String deviceId, double calibration) async {
    await _storage.updatePowerCalibration(deviceId, calibration);
    
    // Update adapter if it's the currently selected device
    if (_selectedPrimaryDevice?.id == deviceId && _primaryAdapter != null) {
      _primaryAdapter!.powerCalibration = calibration;
    }
    
    await _loadDevices();
    notifyListeners();
  }

  /// Delete a device
  Future<void> deleteDevice(String deviceId) async {
    await removeDevice(deviceId);
  }

  /// Refresh devices list
  Future<void> refreshDevices() async {
    await _loadDevices();
  }

  @override
  void dispose() {
    _primaryAdapter?.dispose();
    _hrAdapter?.dispose();
    super.dispose();
  }
}
