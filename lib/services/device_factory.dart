import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/services/adapters/ftms_adapter.dart';
import 'package:free_ride/services/adapters/echelon_adapter.dart';
import 'package:free_ride/services/adapters/heart_rate_adapter.dart';
import 'package:free_ride/services/adapters/virtual_bike_adapter.dart';
import 'package:free_ride/services/adapters/virtual_treadmill_adapter.dart';
import 'package:free_ride/models/saved_device.dart';

/// Factory for creating device adapters and discovering devices
class DeviceFactory {
  static StreamSubscription? _scanSubscription;
  static bool _isScanning = false;

  /// Create adapter instance from saved device configuration
  static DeviceAdapter createAdapter(SavedDevice savedDevice) {
    switch (savedDevice.adapterType) {
      case 'ftms':
        return FTMSAdapter(
          deviceType: savedDevice.deviceType,
          powerCalibration: savedDevice.powerCalibration,
        );
      case 'echelon':
        return EchelonAdapter(
          powerCalibration: savedDevice.powerCalibration,
        );
      case 'heartrate':
        return HeartRateAdapter();
      case 'virtual-bike':
        return VirtualBikeAdapter(
          deviceId: savedDevice.id,
          speed: savedDevice.powerCalibration,
        );
      case 'virtual-treadmill':
        return VirtualTreadmillAdapter(
          deviceId: savedDevice.id,
          speed: savedDevice.powerCalibration,
        );
      default:
        throw Exception('Unknown adapter type: ${savedDevice.adapterType}');
    }
  }

  /// Start discovering compatible devices
  /// Calls onDeviceFound for each discovered device
  /// Returns devices with their detected adapter type and device type
  static Future<void> startDiscovery({
    required Function(BluetoothDevice device, String adapterType, DeviceType deviceType) onDeviceFound,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_isScanning) {
      await stopDiscovery();
    }

    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth not supported on this device');
      }

      // Check if Bluetooth is turned on
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is turned off. Please enable Bluetooth and try again.');
      }

      _isScanning = true;
      final discoveredDevices = <String>{};

      // Start scanning (no service filter to catch all devices)
      await FlutterBluePlus.startScan();

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (var result in results) {
          final device = result.device;
          final deviceId = device.remoteId.toString();

          // Skip if already discovered
          if (discoveredDevices.contains(deviceId)) continue;

          // Detect device type
          final detection = await _detectDeviceType(device, result.advertisementData);
          
          if (detection != null) {
            discoveredDevices.add(deviceId);
            onDeviceFound(device, detection['adapterType']!, detection['deviceType']!);
          }
        }
      });

      // Auto-stop after timeout
      Future.delayed(timeout, () {
        if (_isScanning) {
          stopDiscovery();
        }
      });
    } catch (e) {
      _isScanning = false;
      rethrow;
    }
  }

  /// Stop device discovery
  static Future<void> stopDiscovery() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  /// Detect device type and adapter from advertisement data
  /// Returns map with 'adapterType' and 'deviceType' or null if not compatible
  static Future<Map<String, dynamic>?> _detectDeviceType(
    BluetoothDevice device,
    AdvertisementData advertisementData,
  ) async {
    // Check for Echelon bike (name starts with "ECH")
    final name = advertisementData.advName;
    if (name.startsWith('ECH')) {
      return {
        'adapterType': 'echelon',
        'deviceType': DeviceType.bike,
      };
    }

    // Check for Heart Rate service (0x180D)
    final serviceUuids = advertisementData.serviceUuids.map((g) => g.toString().toLowerCase()).toList();
    if (serviceUuids.any((uuid) => _normalizeUuid(uuid) == '180d')) {
      return {
        'adapterType': 'heartrate',
        'deviceType': DeviceType.heartRateMonitor,
      };
    }

    // Check for FTMS service (0x1826)
    if (serviceUuids.any((uuid) => _normalizeUuid(uuid) == '1826')) {
      // Need to connect to determine if bike or treadmill
      final deviceType = await _determineFTMSDeviceType(device);
      if (deviceType != null) {
        return {
          'adapterType': 'ftms',
          'deviceType': deviceType,
        };
      }
    }

    return null;
  }

  /// Connect to FTMS device to determine if it's a bike or treadmill
  static Future<DeviceType?> _determineFTMSDeviceType(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 5));
      
      final services = await device.discoverServices();
      final ftmsService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == '1826',
        orElse: () => throw Exception('FTMS service not found'),
      );
      
      // Check which characteristics are present
      final hasBikeData = ftmsService.characteristics.any(
        (c) => _normalizeUuid(c.uuid.toString()) == '2ad2', // Indoor Bike Data
      );
      final hasTreadmillData = ftmsService.characteristics.any(
        (c) => _normalizeUuid(c.uuid.toString()) == '2acd', // Treadmill Data
      );
      
      await device.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Prefer bike if both are present
      if (hasBikeData) {
        return DeviceType.bike;
      } else if (hasTreadmillData) {
        return DeviceType.treadmill;
      }
      
      return null;
    } catch (e) {
      try {
        await device.disconnect();
      } catch (_) {}
      return null;
    }
  }

  /// Normalize UUID to short form for comparison
  static String _normalizeUuid(String uuid) {
    final cleaned = uuid.toLowerCase().replaceAll('-', '');
    if (cleaned.length == 32 && cleaned.startsWith('0000') && cleaned.endsWith('00805f9b34fb')) {
      return cleaned.substring(4, 8);
    }
    if (cleaned.length == 4) {
      return cleaned;
    }
    return cleaned;
  }

  /// Test connection to a saved device
  /// Returns true if device is available and can connect
  static Future<bool> testConnection(SavedDevice savedDevice) async {
    try {
      // Virtual devices always "connect" successfully
      if (savedDevice.adapterType == 'virtual-bike' || savedDevice.adapterType == 'virtual-treadmill') {
        return true;
      }
      
      print('[DeviceFactory] Testing connection to: ${savedDevice.address}');
      
      // First check if already connected
      final connectedDevices = await FlutterBluePlus.connectedDevices;
      BluetoothDevice? device = connectedDevices.cast<BluetoothDevice?>().firstWhere(
        (d) => d?.remoteId.toString() == savedDevice.address,
        orElse: () => null,
      );

      if (device != null) {
        print('[DeviceFactory] Device already connected');
        // Try to verify connection is still active
        final state = await device.connectionState.first;
        if (state == BluetoothConnectionState.connected) {
          return true;
        }
      }

      // Device not connected - need to scan for it
      print('[DeviceFactory] Device not connected, scanning...');
      final completer = Completer<BluetoothDevice>();
      StreamSubscription? subscription;
      
      subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (result.device.remoteId.toString() == savedDevice.address) {
            print('[DeviceFactory] Found device in scan');
            if (!completer.isCompleted) {
              completer.complete(result.device);
            }
          }
        }
      });

      // Start scan with timeout
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      
      // Wait for device
      try {
        device = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception('Device not found'),
        );
      } finally {
        subscription.cancel();
        await FlutterBluePlus.stopScan();
      }

      // Connect to the discovered device
      print('[DeviceFactory] Connecting to discovered device...');
      await device.connect(timeout: const Duration(seconds: 10));
      print('[DeviceFactory] Connected successfully');
      
      // Verify connection
      final state = await device.connectionState.first;
      return state == BluetoothConnectionState.connected;
    } catch (e) {
      print('[DeviceFactory] Test connection failed: $e');
      return false;
    }
  }
}

/// Discovered device information
class DiscoveredDevice {
  final BluetoothDevice bluetoothDevice;
  final String name;
  final String address;
  final String adapterType;
  final DeviceType deviceType;
  final int rssi;

  DiscoveredDevice({
    required this.bluetoothDevice,
    required this.name,
    required this.address,
    required this.adapterType,
    required this.deviceType,
    required this.rssi,
  });

  /// Get device type display name
  String get deviceTypeDisplay {
    switch (deviceType) {
      case DeviceType.bike:
        return 'Bike';
      case DeviceType.treadmill:
        return 'Treadmill';
      case DeviceType.heartRateMonitor:
        return 'HR Monitor';
    }
  }

  /// Get adapter type display name
  String get adapterTypeDisplay {
    switch (adapterType) {
      case 'ftms':
        return 'FTMS';
      case 'echelon':
        return 'Echelon';
      case 'heartrate':
        return 'Heart Rate';
      default:
        return adapterType.toUpperCase();
    }
  }
}
