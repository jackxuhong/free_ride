import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';

/// Unified device discovery for all supported fitness device protocols
class UnifiedDeviceDiscovery {
  // Service UUIDs for different protocols
  static const String ftmsServiceUuid = '00001826-0000-1000-8000-00805f9b34fb';
  static const String echelonServiceUuid = '0bf669f1-45f2-11e7-9598-0800200c9a66';

  // Track active scan subscription to prevent duplicates
  static StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Track if a scan is currently in progress
  static bool _isScanning = false;

  // Track if any BLE operation is in progress
  static bool _isBleOperationInProgress = false;

  // Track app start time to prevent BLE operations immediately after restart
  static DateTime? _appStartTime;

  /// Check if enough time has passed since app start to allow BLE operations
  static bool _isTooSoonAfterAppStart() {
    if (_appStartTime == null) {
      _appStartTime = DateTime.now();
      return true; // Always wait at least 2 seconds after first call
    }
    return DateTime.now().difference(_appStartTime!).inSeconds < 2;
  }

  /// Scan for all supported fitness devices
  Future<List<Map<String, dynamic>>> scanForDevices() async {
    // Prevent BLE operations too soon after app start/restart
    if (_isTooSoonAfterAppStart()) {
      await Future.delayed(const Duration(seconds: 2));
    }

    // Prevent concurrent BLE operations
    if (_isBleOperationInProgress) {
      throw Exception('BLE operation already in progress');
    }

    _isBleOperationInProgress = true;

    // Prevent concurrent scans
    if (_isScanning) {
      _isBleOperationInProgress = false;
      throw Exception('Scan already in progress');
    }

    _isScanning = true;
    final deviceInfoList = <Map<String, dynamic>>[];
    final scannedDevices = <String>{}; // Use device address as key

    try {
      // Wait for Bluetooth to be ready
      await _waitForBluetoothReady();

      // Small additional delay to ensure plugin is fully initialized after hot reload
      await Future.delayed(const Duration(milliseconds: 100));

      // Skip all BLE checks during app initialization to avoid conflicts
      // Just proceed with the scan and let it handle any issues

      // Cancel any existing scan subscription
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      // Stop any existing scan
      await FlutterBluePlus.stopScan();

      // Start scanning for all devices (remove service filter to see all BLE devices)
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
      );

      // Collect scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        print('=== SCAN RESULTS BATCH ===');
        print('Scan results received: ${results.length} devices');
        for (var result in results) {
          final deviceAddress = result.device.remoteId.str;
          print('DEVICE FOUND:');
          print('  Name: ${result.device.platformName}');
          print('  Address: $deviceAddress');
          print('  Advertised services: ${result.advertisementData.serviceUuids.length} UUIDs');
          print('  Has service UUIDs: ${result.advertisementData.serviceUuids.isNotEmpty}');
          
          // Log raw UUID details
          if (result.advertisementData.serviceUuids.isNotEmpty) {
            print('  RAW SERVICE UUIDS:');
            for (var service in result.advertisementData.serviceUuids) {
              print('    UUID: $service');
              print('    Type: ${service.runtimeType}');
              print('    String: ${service.toString()}');
            }
          } else {
            print('  NO SERVICES ADVERTISED');
          }

          // Skip if already processed
          if (scannedDevices.contains(deviceAddress)) {
            print('  SKIPPING: Already processed');
            continue;
          }
          scannedDevices.add(deviceAddress);

          // Determine device type based on advertised services
          DeviceType deviceType = DeviceType.indoorBike; // Default
          String protocol = 'unknown';

          // Check advertised services to determine protocol
          for (var service in result.advertisementData.serviceUuids) {
            final serviceStr = service.toString().toLowerCase();
            final serviceGuid = service;
            print('  CHECKING SERVICE: $serviceStr');

            // Try exact string match (case insensitive)
            if (serviceStr == ftmsServiceUuid.toLowerCase()) {
              protocol = 'ftms';
              print('  ✓ MATCHED FTMS (exact string)');
              break;
            } else if (serviceStr == echelonServiceUuid.toLowerCase()) {
              protocol = 'echelon';
              deviceType = DeviceType.indoorBike;
              print('  ✓ MATCHED ECHELON (exact string)');
              break;
            }

            // Try Guid object comparison
            try {
              final ftmsGuid = Guid(ftmsServiceUuid);
              final echelonGuid = Guid(echelonServiceUuid);
              if (serviceGuid == ftmsGuid) {
                protocol = 'ftms';
                print('  ✓ MATCHED FTMS (Guid object)');
                break;
              } else if (serviceGuid == echelonGuid) {
                protocol = 'echelon';
                deviceType = DeviceType.indoorBike;
                print('  ✓ MATCHED ECHELON (Guid object)');
                break;
              }
            } catch (e) {
              print('  ⚠ GUID comparison failed: $e');
            }

            // Try partial string match
            if (serviceStr.contains('1826')) {
              protocol = 'ftms';
              print('  ✓ MATCHED FTMS (partial: 1826)');
              break;
            } else if (serviceStr.contains('f669f1') || serviceStr.contains('45f2')) {
              protocol = 'echelon';
              deviceType = DeviceType.indoorBike;
              print('  ✓ MATCHED ECHELON (partial)');
              break;
            }
          }

          // Fallback: check device name for known fitness device brands
          if (protocol == 'unknown') {
            final deviceName = result.device.platformName.toLowerCase();
            final advName = result.advertisementData.advName.toLowerCase();
            final fullName = deviceName.isNotEmpty ? deviceName : advName;
            print('  CHECKING NAME: "$fullName" (platform: "$deviceName", adv: "$advName")');

            // More permissive Echelon matching - prioritize names starting with ECH
            if (fullName.startsWith('ech')) {
              protocol = 'echelon';
              deviceType = DeviceType.indoorBike;
              print('  ✓ IDENTIFIED ECHELON by name (starts with ECH - high priority)');
            } else if (fullName.contains('echelon') || fullName.contains('connect') || fullName.contains('sport') ||
                fullName.contains('bike') || fullName.contains('exercise') || fullName.contains('fitness')) {
              protocol = 'echelon';
              deviceType = DeviceType.indoorBike;
              print('  ✓ IDENTIFIED ECHELON by name (permissive match)');
            } else if (deviceName.contains('peloton') || deviceName.contains('tacx') || deviceName.contains('wahoo') ||
                       deviceName.contains('zwift') || deviceName.contains('treadmill')) {
              protocol = 'ftms';
              deviceType = deviceName.contains('treadmill') ? DeviceType.treadmill : DeviceType.indoorBike;
              print('  ✓ IDENTIFIED FTMS by name');
            } else {
              print('  ✗ NO MATCH found');
            }
          }

          // Only add devices that are confirmed FTMS or Echelon devices
          if (protocol != 'unknown') {
            print('  RESULT: ADDING DEVICE - Protocol: $protocol, Type: $deviceType');
            deviceInfoList.add({
              'device': result.device,
              'deviceType': deviceType,
              'protocol': protocol,
              'name': result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : result.advertisementData.advName.isNotEmpty
                      ? result.advertisementData.advName
                      : 'Unknown Device',
            });
          } else {
            // Only add Echelon devices identified by name (for devices that don't advertise service UUIDs)
            final deviceName = result.device.platformName.toLowerCase();
            final advName = result.advertisementData.advName.toLowerCase();
            final fullName = deviceName.isNotEmpty ? deviceName : advName;

            if (fullName.startsWith('ech') || fullName.contains('echelon')) {
              print('  RESULT: ADDING DEVICE - Echelon device by name');
              deviceInfoList.add({
                'device': result.device,
                'deviceType': DeviceType.indoorBike,
                'protocol': 'echelon',
                'name': result.device.platformName.isNotEmpty
                    ? result.device.platformName
                    : result.advertisementData.advName.isNotEmpty
                        ? result.advertisementData.advName
                        : 'Unknown Device',
              });
            } else {
              print('  RESULT: SKIPPING DEVICE - Not FTMS or Echelon');
            }
          }
          print(''); // Empty line for readability
        }
      });

      // Wait for scan timeout
      await Future.delayed(const Duration(seconds: 20));

      // Clean up
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _isBleOperationInProgress = false;

      print('=== SCAN COMPLETE ===');
      print('Total devices found: ${scannedDevices.length}');
      print('Supported devices added: ${deviceInfoList.length}');
      print('Scan completed. Found ${deviceInfoList.length} supported devices');

      // Debug: Show what supported devices were found
      if (deviceInfoList.isNotEmpty) {
        print('Supported devices:');
        for (var device in deviceInfoList) {
          print('  - ${device['name']} (${device['protocol']})');
        }
      } else {
        print('No FTMS or Echelon devices found. This could be because:');
        print('  1. No devices advertise FTMS (00001826-0000-1000-8000-00805f9b34fb) service UUID');
        print('  2. No devices advertise Echelon (0bf669f1-45f2-11e7-9598-0800200c9a66) service UUID');
        print('  3. No devices have names starting with "ECH" or containing "echelon"');
        print('  4. Fitness devices not powered on or in range');
        print('  5. BLE permissions or adapter issues');
      }

      return deviceInfoList;

    } catch (e) {
      // Clean up on error
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _isBleOperationInProgress = false;
      rethrow;
    }
  }

  /// Get device protocol from device info
  static String getDeviceProtocol(Map<String, dynamic> deviceInfo) {
    return deviceInfo['protocol'] as String? ?? 'unknown';
  }

  /// Wait for Bluetooth to be ready
  static Future<void> _waitForBluetoothReady() async {
    // Simple delay to allow BLE system to stabilize after app start/restart
    await Future.delayed(const Duration(seconds: 1));
  }

  /// Check if a scan is currently in progress
  static bool get isScanning => _isScanning;

  /// Check if any BLE operation is currently in progress
  static bool get isBleOperationInProgress => _isBleOperationInProgress;
}