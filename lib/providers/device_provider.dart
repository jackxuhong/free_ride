import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/ftms_service.dart';
import 'package:free_ride/services/device_factory.dart';

class DeviceProvider extends ChangeNotifier {
  final DeviceStorageService _storage = DeviceStorageService();
  final DeviceFactoryRegistry _factoryRegistry = DeviceFactoryRegistry();

  FitnessDevice? _selectedDevice;
  VirtualFitnessDevice? _activeDevice;
  bool _isScanning = false;
  List<FitnessDevice> _availableDevices = [];

  FitnessDevice? get selectedDevice => _selectedDevice;
  VirtualFitnessDevice? get activeDevice => _activeDevice;
  bool get isScanning => _isScanning;
  List<FitnessDevice> get availableDevices => _availableDevices;
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
  Future<void> selectDevice(FitnessDevice device) async {
    // Dispose old active device if it exists
    if (_activeDevice != null && _selectedDevice?.id != device.id) {
      _activeDevice?.dispose();
      _activeDevice = null;
    }
    
    _selectedDevice = device;
    await _storage.setLastUsedDeviceId(device.id);
    
    // Only create new active device if we don't have one or device changed
    if (_activeDevice == null) {
      _activeDevice = _createActiveDevice(device);
    }
    
    notifyListeners();
  }

  /// Create active device instance based on type
  VirtualFitnessDevice _createActiveDevice(FitnessDevice device) {
    return _factoryRegistry.createDevice(device);
  }

  /// Remove a device
  Future<void> removeDevice(String deviceId) async {
    // Don't allow removing virtual devices
    final device = _storage.getDevice(deviceId);
    if (device?.isVirtual == true) {
      throw Exception('Cannot remove virtual devices');
    }
    
    // Dispose active device if removing the selected one
    if (_selectedDevice?.id == deviceId) {
      _activeDevice?.dispose();
      _activeDevice = null;
      _selectedDevice = null;
    }
    
    await _storage.deleteDevice(deviceId);
    await _loadDevices();
    notifyListeners();
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
    
    // Reload devices and update parameters for virtual devices only
    await _loadDevices();
    if (_selectedDevice?.id == deviceId) {
      final device = _storage.getDevice(deviceId);
      if (device != null) {
        _selectedDevice = device;
        
        // Only recreate active device for virtual devices
        // Real FTMS devices should maintain their connection
        if (device.isVirtual && _activeDevice != null) {
          _activeDevice?.dispose();
          _activeDevice = _createActiveDevice(device);
        }
        
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
      // Scan for FTMS devices with type detection
      final deviceInfoList = await FTMSService.scanForDevices();
      
      // Convert to FitnessDevice models and save
      for (var deviceInfo in deviceInfoList) {
        final bleDevice = deviceInfo['device'] as BluetoothDevice;
        final deviceType = deviceInfo['deviceType'] as DeviceType;
        
        // Check if already saved
        final existing = _availableDevices.where((d) => d.deviceAddress == bleDevice.remoteId.str).firstOrNull;
        if (existing == null) {
          final device = FitnessDevice(
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
