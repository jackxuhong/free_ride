import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';

/// Handles discovery of FTMS devices via Bluetooth scanning
class FTMSDeviceDiscovery {
  // FTMS UUIDs
  static const String ftmsServiceUuid = '00001826-0000-1000-8000-00805f9b34fb';
  static const String indoorBikeDataUuid = '00002ad2-0000-1000-8000-00805f9b34fb';
  static const String treadmillDataUuid = '00002acd-0000-1000-8000-00805f9b34fb';

  /// Normalize UUID to short form for comparison
  static String _normalizeUuid(String uuid) {
    final cleaned = uuid.toLowerCase().replaceAll('-', '');
    // If it's a standard Bluetooth UUID (128-bit with base), extract the 16-bit part
    if (cleaned.length == 32 && cleaned.startsWith('0000') && cleaned.endsWith('00805f9b34fb')) {
      return cleaned.substring(4, 8);
    }
    // If it's already short form (4 characters), return as is
    if (cleaned.length == 4) {
      return cleaned;
    }
    // Otherwise return the full UUID
    return cleaned;
  }

  /// Scan for FTMS devices
  Future<List<Map<String, dynamic>>> scanForDevices() async {
    final deviceInfoList = <Map<String, dynamic>>[];
    final scannedDevices = <BluetoothDevice>[];

    try {
      // Check if Bluetooth is available
      if (await FlutterBluePlus.isSupported == false) {
        throw Exception('Bluetooth not supported on this device');
      }

      // Start scanning for FTMS service
      await FlutterBluePlus.startScan(
        withServices: [Guid(ftmsServiceUuid)],
        timeout: const Duration(seconds: 10),
      );

      // Listen to scan results
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (!scannedDevices.contains(result.device)) {
            scannedDevices.add(result.device);
          }
        }
      });

      await Future.delayed(const Duration(seconds: 10));
      await subscription.cancel();
      await FlutterBluePlus.stopScan();

      // Now connect to each device to determine its type
      for (var device in scannedDevices) {
        try {
          // print('Connecting to ${device.platformName} to determine type...');
          await device.connect(timeout: const Duration(seconds: 5));

          // Discover services
          final services = await device.discoverServices();
          final ftmsService = services.firstWhere(
            (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(ftmsServiceUuid),
            orElse: () => throw Exception('FTMS service not found'),
          );

          // Check which characteristics are present
          final hasBikeData = ftmsService.characteristics.any(
            (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(indoorBikeDataUuid),
          );
          final hasTreadmillData = ftmsService.characteristics.any(
            (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(treadmillDataUuid),
          );

          // Determine device type - prefer bike if both are present
          DeviceType deviceType = DeviceType.indoorBike; // default
          if (hasTreadmillData && !hasBikeData) {
            deviceType = DeviceType.treadmill;
          }

          deviceInfoList.add({
            'device': device,
            'deviceType': deviceType,
          });

          // Disconnect after getting info and wait for disconnect to complete
          await device.disconnect();
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('Error connecting to ${device.platformName}: $e');
          // Add with default type if connection fails
          deviceInfoList.add({
            'device': device,
            'deviceType': DeviceType.indoorBike,
          });
          try {
            await device.disconnect();
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Error scanning for devices: $e');
    }

    return deviceInfoList;
  }
}