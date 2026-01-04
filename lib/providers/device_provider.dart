import 'package:flutter/foundation.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/virtual_indoor_bike.dart';
import 'package:free_ride/services/virtual_treadmill.dart';
import 'package:free_ride/services/ftms_service.dart';

class DeviceProvider extends ChangeNotifier {
  final DeviceStorageService _storage = DeviceStorageService();

  FTMSDevice? _selectedDevice;
  VirtualFitnessDevice? _activeDevice;
  bool _isScanning = false;
  List<FTMSDevice> _availableDevices = [];

  FTMSDevice? get selectedDevice => _selectedDevice;
  VirtualFitnessDevice? get activeDevice => _activeDevice;
  bool get isScanning => _isScanning;
  List<FTMSDevice> get availableDevices => _availableDevices;
  bool get hasDeviceSelected => _selectedDevice != null;

  /// Initialize provider and load last used device
  Future<void> init() async {
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
  Future<void> selectDevice(FTMSDevice device) async {
    _selectedDevice = device;
    await _storage.setLastUsedDeviceId(device.id);
    
    // Create active device instance
    _activeDevice = _createActiveDevice(device);
    
    notifyListeners();
  }

  /// Create active device instance based on type
  VirtualFitnessDevice _createActiveDevice(FTMSDevice device) {
    if (device.isVirtual) {
      // Create virtual device
      if (device.deviceType == DeviceType.indoorBike) {
        return VirtualIndoorBike(
          targetSpeed: device.effortLevel,
        );
      } else {
        return VirtualTreadmill(
          userSpeed: device.effortLevel,
        );
      }
    } else {
      // Create FTMS service for real device
      return FTMSService(device: device);
    }
  }

  /// Update virtual device parameters
  Future<void> updateDeviceParameters({
    required String deviceId,
    double? effortLevel,
    double? controllableParam,
  }) async {
    await _storage.updateDeviceParameters(
      deviceId,
      effortLevel: effortLevel,
      controllableParam: controllableParam,
    );
    
    // Reload devices and recreate active device if this is selected device
    await _loadDevices();
    if (_selectedDevice?.id == deviceId) {
      final device = _storage.getDevice(deviceId);
      if (device != null) {
        _selectedDevice = device;
        _activeDevice = _createActiveDevice(device);
        notifyListeners();
      }
    }
  }

  /// Start scanning for real FTMS devices
  Future<void> startScan() async {
    if (_isScanning) return;
    
    _isScanning = true;
    notifyListeners();

    try {
      // Scan for FTMS devices
      final devices = await FTMSService.scanForDevices();
      
      // Convert to FTMSDevice models and save
      for (var bleDevice in devices) {
        // Check if already saved
        final existing = _availableDevices.where((d) => d.deviceAddress == bleDevice.remoteId.str).firstOrNull;
        if (existing == null) {
          final device = FTMSDevice(
            id: bleDevice.remoteId.str,
            name: bleDevice.platformName.isNotEmpty ? bleDevice.platformName : 'FTMS Device',
            deviceType: DeviceType.indoorBike, // Default, will be determined on connect
            isVirtual: false,
            deviceAddress: bleDevice.remoteId.str,
          );
          await _storage.saveDevice(device);
        }
      }

      await _loadDevices();
    } catch (e) {
      debugPrint('Error scanning: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop scanning
  Future<void> stopScan() async {
    _isScanning = false;
    notifyListeners();
  }

  /// Delete a device
  Future<void> deleteDevice(String deviceId) async {
    await _storage.deleteDevice(deviceId);
    
    // If deleted device was selected, clear selection
    if (_selectedDevice?.id == deviceId) {
      _selectedDevice = null;
      _activeDevice?.dispose();
      _activeDevice = null;
    }
    
    await _loadDevices();
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
