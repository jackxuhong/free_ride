import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/virtual_indoor_bike.dart';
import 'package:free_ride/services/virtual_treadmill.dart';
import 'package:free_ride/services/ftms_service.dart';

class DeviceProvider extends ChangeNotifier {
    /// Local cache of discovered/tested device addresses
    final Set<String> _deviceCache = <String>{};
  final DeviceStorageService _storage = DeviceStorageService();

  /// Service detector functions registry
  /// Each detector attempts to identify and configure a BLE device
  static final List<Future<FTMSDevice?> Function(BluetoothDevice)> _detectors = [
    FTMSService.detectDevice,
    // Future device services can be registered here
  ];

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
      // Create FTMS service for real device (don't connect yet)
      // Connection will be initiated when ride starts
      return FTMSService(device: device);
    }
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

  /// Start scanning for all BLE devices
  Future<void> startScan() async {
    if (_isScanning) return;

    developer.log('Starting BLE device scan...', name: 'DeviceProvider');
    _isScanning = true;
    notifyListeners();

    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        developer.log('Bluetooth not supported on this device', name: 'DeviceProvider', level: 1000);
        throw Exception('Bluetooth not supported on this device');
      }

      // Check Bluetooth adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      developer.log('Bluetooth adapter state: $adapterState', name: 'DeviceProvider');
      
      if (adapterState != BluetoothAdapterState.on) {
        developer.log('Waiting for Bluetooth to turn on...', name: 'DeviceProvider', level: 900);
        // Wait for Bluetooth to turn on (with timeout)
        final stateCompleter = Completer<void>();
        StreamSubscription? stateSubscription;
        
        stateSubscription = FlutterBluePlus.adapterState.listen((state) {
          developer.log('Bluetooth state changed to: $state', name: 'DeviceProvider');
          if (state == BluetoothAdapterState.on) {
            stateCompleter.complete();
            stateSubscription?.cancel();
          }
        });
        
        // Wait up to 5 seconds for Bluetooth to turn on
        await stateCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            stateSubscription?.cancel();
            developer.log('Bluetooth did not turn on within 5 seconds', name: 'DeviceProvider', level: 1000);
            throw Exception('Bluetooth is not turned on. Please enable Bluetooth and try again.');
          },
        );
        developer.log('Bluetooth is now ready', name: 'DeviceProvider');
      }

      // Scan for ALL BLE devices (no service filter)
      final scannedDevices = <BluetoothDevice>[];

      // Set up scan results listener BEFORE starting scan
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (!scannedDevices.contains(result.device)) {
            scannedDevices.add(result.device);
            developer.log('Found BLE device: ${result.device.platformName.isNotEmpty ? result.device.platformName : result.device.remoteId}', name: 'DeviceProvider');
          }
        }
      });

      try {
        // Start scan with timeout (will auto-stop after 10 seconds)
        developer.log('Starting BLE scan (10 second timeout)...', name: 'DeviceProvider');
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 10),
        );

        // Wait for scan to complete (timeout will handle stopping)
        await Future.delayed(const Duration(seconds: 10));
        developer.log('BLE scan completed. Found ${scannedDevices.length} devices', name: 'DeviceProvider');
      } finally {
        // Clean up subscription
        await subscription.cancel();
      }

      // Process each discovered device sequentially
      developer.log('Processing ${scannedDevices.length} discovered devices...', name: 'DeviceProvider');
      for (var bleDevice in scannedDevices) {
        // Skip devices with no name (often not fitness equipment)
        if (bleDevice.platformName.isEmpty) {
          developer.log('Skipping unnamed device: ${bleDevice.remoteId}', name: 'DeviceProvider');
          continue;
        }

        // Skip if already discovered/tested in cache
        final cacheKey = bleDevice.remoteId.toString();
        if (_deviceCache.contains(cacheKey)) {
          developer.log('Skipping cached device: ${bleDevice.platformName}', name: 'DeviceProvider');
          continue;
        }

        developer.log('Testing device: ${bleDevice.platformName}', name: 'DeviceProvider');

        // Try each registered detector
        for (var detector in _detectors) {
          try {
            final ftmsDevice = await detector(bleDevice);

            if (ftmsDevice != null) {
              // Device detected! Check if already saved
              final existing = _availableDevices
                  .where((d) => d.deviceAddress == ftmsDevice.deviceAddress)
                  .firstOrNull;

              if (existing == null) {
                // Save new device
                await _storage.saveDevice(ftmsDevice);
                developer.log('Discovered new ${ftmsDevice.deviceType.name}: ${ftmsDevice.name}', name: 'DeviceProvider', level: 800);
                debugPrint('Discovered ${ftmsDevice.deviceType.name}: ${ftmsDevice.name}');
              } else {
                // Update last connected time
                final updated = existing.copyWith(lastConnected: DateTime.now());
                await _storage.saveDevice(updated);
                developer.log('Updated existing device: ${ftmsDevice.name}', name: 'DeviceProvider');
              }

              // Add to cache
              _deviceCache.add(cacheKey);
              // First match wins - stop checking other detectors
              break;
            } else {
              developer.log('Device ${bleDevice.platformName} not supported by this detector', name: 'DeviceProvider');
            }
          } catch (e) {
            developer.log('Detector error for ${bleDevice.platformName}: $e', name: 'DeviceProvider', level: 900, error: e);
            debugPrint('Detector error for ${bleDevice.platformName}: $e');
            // Continue to next detector
          }
        }
        // Add to cache even if not supported (so we don't test again)
        _deviceCache.add(cacheKey);
      }

      // Reload devices list
      await _loadDevices();
      developer.log('Device scan completed. Total devices available: ${_availableDevices.length}', name: 'DeviceProvider', level: 800);
    } catch (e) {
      developer.log('Error scanning: $e', name: 'DeviceProvider', level: 1000, error: e);
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

  /// Clear the local device cache
  void clearDeviceCache() {
    _deviceCache.clear();
    developer.log('Device cache cleared', name: 'DeviceProvider');
    notifyListeners();
  }

  @override
  void dispose() {
    _activeDevice?.dispose();
    super.dispose();
  }
}
