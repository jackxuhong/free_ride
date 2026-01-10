import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/services/adapters/ftms_adapter.dart';
import 'package:free_ride/services/adapters/virtual_bike_adapter.dart';
import 'package:free_ride/services/adapters/virtual_treadmill_adapter.dart';

/// Factory for creating and managing device adapters
class DeviceFactory {
  static bool _isDiscovering = false;

  /// Create an appropriate adapter based on SavedDevice configuration
  static DeviceAdapter createAdapter(SavedDevice device) {
    late DeviceAdapter adapter;
    
    switch (device.adapterType) {
      case 'virtual-bike':
        adapter = VirtualBikeAdapter(
          deviceId: device.id,
          powerCalibration: device.powerCalibration,
        );
        break;
      
      case 'virtual-treadmill':
        adapter = VirtualTreadmillAdapter(
          deviceId: device.id,
          powerCalibration: device.powerCalibration,
        );
        break;
      
      case 'ftms':
      default:
        // Determine device type from saved device type
        final deviceType = device.deviceType;
        adapter = FTMSAdapter(
          deviceType: deviceType,
          powerCalibration: device.powerCalibration,
        );
    }
    
    // Apply saved configuration to the adapter
    if (device.configurations.isNotEmpty) {
      adapter.applyConfiguration(device.configurations);
    }
    
    return adapter;
  }

  /// Start discovery for Bluetooth fitness devices
  static Future<void> startDiscovery({
    required Function(BluetoothDevice device, String adapterType, DeviceType deviceType) onDeviceFound,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_isDiscovering) return;
    
    _isDiscovering = true;
    
    try {
      // Start Bluetooth scan
      await FlutterBluePlus.startScan(timeout: timeout);
      
      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final device = result.device;
          
          // Detect device type based on advertising data
          final adapterType = _detectAdapterType(result);
          final deviceType = _detectDeviceType(result);
          
          if (adapterType != null && deviceType != null) {
            onDeviceFound(device, adapterType, deviceType);
          }
        }
      });
    } catch (e) {
      _isDiscovering = false;
      rethrow;
    }
  }

  /// Stop device discovery
  static Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    
    try {
      await FlutterBluePlus.stopScan();
      _isDiscovering = false;
    } catch (e) {
      _isDiscovering = false;
      rethrow;
    }
  }

  /// Test connection to a saved device
  static Future<bool> testConnection(SavedDevice device) async {
    try {
      final adapter = createAdapter(device);
      
      // For virtual devices, always return true
      if (device.adapterType.startsWith('virtual-')) {
        return true;
      }
      
      // For real devices, attempt connection
      final result = await adapter.connect(device).timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      
      // Clean up
      await adapter.disconnect();
      
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Detect adapter type from Bluetooth advertising data
  static String? _detectAdapterType(ScanResult result) {
    // Check device name for FTMS indicators
    final name = result.device.platformName.toLowerCase();
    if (name.isEmpty) return 'ftms';
    
    // Check for common FTMS device names
    if (name.contains('ftms') || 
        name.contains('indoor') || 
        name.contains('fitness') ||
        name.contains('peloton') ||
        name.contains('echelon')) {
      return 'ftms';
    }
    
    // Default to FTMS for unknown devices
    return 'ftms';
  }

  /// Detect device type from Bluetooth name or advertising data
  static DeviceType? _detectDeviceType(ScanResult result) {
    final name = result.device.platformName.toLowerCase();
    
    // Check device name for clues
    if (name.contains('bike') || name.contains('peloton') || name.contains('indoor') || name.contains('echelon')) {
      return DeviceType.indoorBike;
    }
    
    if (name.contains('treadmill') || name.contains('tread') || name.contains('run')) {
      return DeviceType.treadmill;
    }
    
    // Default to bike if unknown
    return DeviceType.indoorBike;
  }
}
