import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart' as model;
import 'package:free_ride/services/fitness_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// FTMS Bluetooth service for real fitness equipment
/// This is a stub implementation - full Bluetooth integration to be completed
class FTMSDevice implements FitnessDevice {
  final model.FTMSDevice device;
  final model.DeviceType _deviceType;
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionStateSubscription;
  bool _isReconnecting = false;
  bool _isConnected = false;
  
  // Device capabilities
  int _minResistance = 1;
  int _maxResistance = 20;
  double _minIncline = -3.0;
  double _maxIncline = 15.0;
  
  final StreamController<DeviceDataSnapshot> _dataController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  DeviceDataSnapshot? _lastSnapshot;
  
  /// Stream of connection state (true = connected, false = disconnected)
  Stream<bool> get connectionState => _connectionStateController.stream;
  
  /// Current connection state
  bool get isConnected => _isConnected;
  
  /// Device resistance range
  int get minResistance => _minResistance;
  int get maxResistance => _maxResistance;
  
  /// Device incline range
  double get minIncline => _minIncline;
  double get maxIncline => _maxIncline;

  // FTMS UUIDs
  static const String ftmsServiceUuid = '00001826-0000-1000-8000-00805f9b34fb';
  static const String indoorBikeDataUuid = '00002ad2-0000-1000-8000-00805f9b34fb';
  static const String treadmillDataUuid = '00002acd-0000-1000-8000-00805f9b34fb';
  static const String controlPointUuid = '00002ad9-0000-1000-8000-00805f9b34fb';
  static const String resistanceRangeUuid = '00002ad6-0000-1000-8000-00805f9b34fb';
  static const String inclineRangeUuid = '00002ad5-0000-1000-8000-00805f9b34fb';
  static const String featureUuid = '00002acc-0000-1000-8000-00805f9b34fb';
  
  /// Normalize UUID to short form for comparison (e.g., "1826" or "00001826-0000-1000-8000-00805f9b34fb" -> "1826")
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

  /// Detect if a BLE device is a supported FTMS device
  /// Returns FTMSDevice if supported, null otherwise
  static Future<model.FTMSDevice?> detectDevice(BluetoothDevice bleDevice) async {
    // Skip unnamed devices — they are never FTMS fitness equipment
    if (bleDevice.platformName.isEmpty) {
      return null;
    }

    try {
      // Connect to device with timeout
      await bleDevice.connect(timeout: const Duration(seconds: 5));
      
      // Discover services
      final services = await bleDevice.discoverServices();
      
      // Check if FTMS service exists
      final ftmsService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(ftmsServiceUuid),
        orElse: () => throw Exception('FTMS service not found'),
      );
      
      // Check which characteristics are present to determine device type
      final hasBikeData = ftmsService.characteristics.any(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(indoorBikeDataUuid),
      );
      final hasTreadmillData = ftmsService.characteristics.any(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(treadmillDataUuid),
      );
      
      // Disconnect after detection
      await bleDevice.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Determine device type - prefer bike if both are present
      model.DeviceType deviceType = model.DeviceType.indoorBike;
      if (hasTreadmillData && !hasBikeData) {
        deviceType = model.DeviceType.treadmill;
      }
      
      // Return FTMSDevice model
      final device = model.FTMSDevice(
        id: bleDevice.remoteId.str,
        name: bleDevice.platformName.isNotEmpty 
            ? bleDevice.platformName 
            : 'FTMS Device',
        deviceType: deviceType,
        isVirtual: false,
        deviceAddress: bleDevice.remoteId.str,
        lastConnected: DateTime.now(),
      );
      developer.log('Detected FTMS device: ${device.name} (${device.deviceAddress})', name: 'FTMSService', level: 1000);
      return device;
    } catch (e) {
      // Check if it's a timeout - if so, rethrow so provider can handle retry logic
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
        developer.log('Connection timeout for FTMS device - rethrowing for retry', name: 'FTMSService');
        try {
          await bleDevice.disconnect();
        } catch (_) {}
        rethrow; // Let provider handle timeout
      }
      
      // Not a supported FTMS device or connection failed
      try {
        await bleDevice.disconnect();
      } catch (_) {}
      return null;
    }
  }

  FTMSDevice({required this.device}) : _deviceType = device.deviceType;

  @override
  model.DeviceType get deviceType => _deviceType;

  /// Connect to the device
  Future<bool> connect() async {
    try {
      if (device.deviceAddress == null) {
        developer.log('Cannot connect: device address is null', name: 'FTMSService', level: 1000);
        return false;
      }

      developer.log('Attempting to connect to device: ${device.name}', name: 'FTMSService');
      
      // Get all connected and available devices
      final connectedDevices = FlutterBluePlus.connectedDevices;
      _connectedDevice = connectedDevices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () => BluetoothDevice(remoteId: DeviceIdentifier(device.deviceAddress!)),
      );

      // Check current connection state
      final connectionState = await _connectedDevice!.connectionState.first;
      developer.log('Current connection state: $connectionState', name: 'FTMSService');
      
      // Connect if not already connected
      if (connectionState == BluetoothConnectionState.disconnected) {
        developer.log('Connecting to device...', name: 'FTMSService');
        await _connectedDevice!.connect(timeout: const Duration(seconds: 15));
        developer.log('Connected successfully', name: 'FTMSService');
      } else {
        developer.log('Device already connected', name: 'FTMSService');
      }

      // Discover services
      developer.log('Discovering services...', name: 'FTMSService');
      final services = await _connectedDevice!.discoverServices();
      developer.log('Found ${services.length} services', name: 'FTMSService');
      
      // Log all service UUIDs for debugging
      developer.log('Available services:', name: 'FTMSService');
      for (var service in services) {
        developer.log('  - ${service.uuid.toString()}', name: 'FTMSService');
      }
      developer.log('Looking for FTMS service: $ftmsServiceUuid', name: 'FTMSService');
      
      // Find FTMS service
      final ftmsService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(ftmsServiceUuid),
        orElse: () => throw Exception('FTMS service not found'),
      );
      developer.log('Found FTMS service with ${ftmsService.characteristics.length} characteristics', name: 'FTMSService');
      
      // Read device capabilities for bikes
      if (_deviceType == model.DeviceType.indoorBike) {
        // Read fitness machine features (silently)
        try {
          final featureChar = ftmsService.characteristics.firstWhere(
            (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(featureUuid),
          );
          await featureChar.read();
        } catch (e) {
          // Features not available
        }
        
        try {
          final resistanceRangeChar = ftmsService.characteristics.firstWhere(
            (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(resistanceRangeUuid),
          );
          final value = await resistanceRangeChar.read();
          if (value.length >= 6) {
            // Format: min (sint16), max (sint16), increment (uint16)
            _minResistance = ByteData.sublistView(Uint8List.fromList(value.sublist(0, 2))).getInt16(0, Endian.little);
            _maxResistance = ByteData.sublistView(Uint8List.fromList(value.sublist(2, 4))).getInt16(0, Endian.little);
          }
        } catch (e) {
          // Use defaults if characteristic not found or read fails
        }
      }
      
      // Read incline range for treadmills
      if (_deviceType == model.DeviceType.treadmill) {
        try {
          final inclineRangeChar = ftmsService.characteristics.firstWhere(
            (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(inclineRangeUuid),
          );
          final value = await inclineRangeChar.read();
          if (value.length >= 6) {
            // Format: min (sint16), max (sint16), increment (uint16)
            // Values are in 0.1% resolution
            _minIncline = ByteData.sublistView(Uint8List.fromList(value.sublist(0, 2))).getInt16(0, Endian.little) / 10.0;
            _maxIncline = ByteData.sublistView(Uint8List.fromList(value.sublist(2, 4))).getInt16(0, Endian.little) / 10.0;
          }
        } catch (e) {
          // Use defaults if characteristic not found or read fails
        }
      }

      // Find the appropriate data characteristic based on device type
        final dataCharUuid = _deviceType == model.DeviceType.indoorBike 
          ? indoorBikeDataUuid 
          : treadmillDataUuid;
      
      _dataCharacteristic = ftmsService.characteristics.firstWhere(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(dataCharUuid),
        orElse: () => throw Exception('Data characteristic not found'),
      );
      
      // Find and cache the control point characteristic
      try {
        _controlCharacteristic = ftmsService.characteristics.firstWhere(
          (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(controlPointUuid),
        );
        
        // Subscribe to control point notifications to receive responses
        await _controlCharacteristic!.setNotifyValue(true);
        _controlCharacteristic!.lastValueStream.listen((value) {
          // Control point responses received
        });
        
        // Request control (opcode 0x00)
        try {
          await _controlCharacteristic!.write([0x00], withoutResponse: false);
        } catch (e) {
          // Could not request control
        }
      } catch (e) {
        // Control point not available
      }

      // Subscribe to notifications
      await _dataCharacteristic!.setNotifyValue(true);
      
      _dataSubscription = _dataCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
            final snapshot = _deviceType == model.DeviceType.indoorBike
              ? _parseIndoorBikeData(value)
              : _parseTreadmillData(value);
          _lastSnapshot = snapshot;
          _dataController.add(snapshot);
        }
      });
      
      // Monitor connection state for auto-reconnection
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_isReconnecting) {
          _isConnected = false;
          _connectionStateController.add(false);
          developer.log('FTMS device disconnected, attempting to reconnect...', name: 'FTMSService', level: 900);
          _attemptReconnect();
        }
      });
      
      _isConnected = true;
      _connectionStateController.add(true);

      return true;
    } catch (e) {
      developer.log('Error connecting to device: $e', name: 'FTMSService', level: 1000, error: e);
      await disconnect();
      
      // Trigger auto-reconnect for initial connection failures
      if (!_isReconnecting) {
        _attemptReconnect();
      }
      
      return false;
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    _isReconnecting = false; // Stop any reconnection attempts
    _isConnected = false;
    _connectionStateController.add(false);
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
  }
  
  /// Attempt to reconnect to device
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    
    // Wait a bit before reconnecting
    await Future.delayed(const Duration(seconds: 2));
    
    if (!_isReconnecting) return; // Cancelled during wait
    
    final success = await connect();
    if (success) {
      developer.log('Successfully reconnected to FTMS device', name: 'FTMSService', level: 800);
      _isReconnecting = false;
    } else {
      developer.log('Reconnection failed, will retry...', name: 'FTMSService', level: 900);
      _isReconnecting = false;
      // Will trigger again via connection state listener
    }
  }

  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    // Real devices don't use updateInputs - data comes from device
  }

  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // Real devices don't simulate - they provide actual data
    // Return last received data or default
    return _lastSnapshot ?? DeviceDataSnapshot();
  }

  @override
  Future<bool> sendControlCommand(ControlCommand command) async {
    try {
      if (_controlCharacteristic == null) {
        developer.log('Control characteristic not available', name: 'FTMSService', level: 900);
        return false;
      }
      
      if (!_isConnected) {
        developer.log('Device not connected, cannot send control command', name: 'FTMSService', level: 900);
        return false;
      }

      // Build command packet based on command type
      List<int> packet;
      switch (command) {
        case SetResistance(level: final level):
          // For bikes with simulation support, use simulation parameters instead
          // Opcode 0x11: Set Indoor Bike Simulation Parameters
          // Calculate grade from resistance level
          final gradePercent = ((level - _minResistance - (_maxResistance - _minResistance) * 0.25) * 20.0 / (_maxResistance - _minResistance)).clamp(-5.0, 15.0);
          final windSpeed = 0; // 0 m/s
          final grade = (gradePercent * 100).round(); // Convert to 0.01% resolution
          final crr = 40; // 0.004 (typical rolling resistance)
          final windResistance = 40; // 0.4 kg/m (typical)
          
          packet = [
            0x11, // Opcode: Set Indoor Bike Simulation Parameters
            windSpeed & 0xFF, (windSpeed >> 8) & 0xFF, // Wind speed (sint16, 0.001 m/s resolution)
            grade & 0xFF, (grade >> 8) & 0xFF, // Grade (sint16, 0.01% resolution)
            crr, // Coefficient of rolling resistance (uint8, 0.0001 resolution)
            windResistance, // Wind resistance coefficient (uint8, 0.01 kg/m resolution)
          ];
        case SetIncline(percentage: final percentage):
          // Opcode 0x06: Set Target Inclination
          final inclineValue = (percentage * 10).round(); // Resolution 0.1%
          packet = [
            0x06,
            inclineValue & 0xFF,
            (inclineValue >> 8) & 0xFF,
          ];
      }

      await _controlCharacteristic!.write(packet, withoutResponse: false);
      return true;
    } catch (e) {
      developer.log('Error sending control command: $e', name: 'FTMSService', level: 1000, error: e);
      return false;
    }
  }

  @override
  Uint8List getFTMSDataPacket() {
    // Real devices don't generate packets - they receive them
    return Uint8List(0);
  }

  /// Parses Indoor Bike Data characteristic (UUID 0x2AD2) per FTMS spec.
  ///
  /// Fields are consumed in bit-flag order so that unrecognised but flagged
  /// fields are properly skipped and downstream offsets remain correct.
  DeviceDataSnapshot _parseIndoorBikeData(List<int> data) {
    if (data.length < 4) return DeviceDataSnapshot();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    double? cadence;
    double? power;
    int? heartRate;
    double? resistance;

    // Instantaneous Speed — always present (uint16, 0.01 km/h)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01;
      offset += 2;
    }

    // Bit 1 — Average Speed (uint16, 0.01 km/h)
    if ((flags & 0x02) != 0) {
      offset += 2; // skip
    }

    // Bit 2 — Instantaneous Cadence (uint16, 0.5 RPM)
    if ((flags & 0x04) != 0 && offset + 2 <= data.length) {
      final cadenceRaw = data[offset] | (data[offset + 1] << 8);
      cadence = cadenceRaw * 0.5;
      offset += 2;
    }

    // Bit 3 — Average Cadence (uint16)
    if ((flags & 0x08) != 0) {
      offset += 2; // skip
    }

    // Bit 4 — Total Distance (uint24)
    if ((flags & 0x10) != 0) {
      offset += 3; // skip
    }

    // Bit 5 — Resistance Level (sint16)
    if ((flags & 0x20) != 0 && offset + 2 <= data.length) {
      final resistanceRaw = data[offset] | (data[offset + 1] << 8);
      resistance = resistanceRaw.toDouble();
      offset += 2;
    }

    // Bit 6 — Instantaneous Power (sint16, 1 W)
    if ((flags & 0x40) != 0 && offset + 2 <= data.length) {
      final powerRaw = data[offset] | (data[offset + 1] << 8);
      power = powerRaw.toDouble();
      offset += 2;
    }

    // Bit 7 — Average Power (sint16)
    if ((flags & 0x80) != 0) {
      offset += 2; // skip
    }

    // Bit 8 — Expended Energy (uint16 total + uint16 per hour + uint8 per min)
    if ((flags & 0x100) != 0) {
      offset += 5; // skip
    }

    // Bit 9 — Heart Rate (uint8)
    if ((flags & 0x200) != 0 && offset + 1 <= data.length) {
      heartRate = data[offset];
      offset += 1;
    }

    return DeviceDataSnapshot(
      speed: speed,
      power: power,
      cadenceOrPace: cadence,
      heartRate: heartRate,
      controllableParam: resistance,
    );
  }

  /// Parses Treadmill Data characteristic (UUID 0x2ACD) per FTMS spec.
  ///
  /// Consumes fields in bit-flag order to keep offsets correct.
  DeviceDataSnapshot _parseTreadmillData(List<int> data) {
    if (data.length < 4) return DeviceDataSnapshot();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    double? pace;
    double? incline;
    int? heartRate;

    // Instantaneous Speed — always present (uint16, 0.01 km/h)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01;
      offset += 2;
    }

    // Bit 1 — Average Speed (uint16)
    if ((flags & 0x02) != 0) {
      offset += 2;
    }

    // Bit 2 — Total Distance (uint24)
    if ((flags & 0x04) != 0) {
      offset += 3;
    }

    // Bit 3 — Inclination + Ramp Angle (sint16 + sint16)
    if ((flags & 0x08) != 0 && offset + 4 <= data.length) {
      final inclineRaw = ByteData.sublistView(
        Uint8List.fromList(data.sublist(offset, offset + 2)),
      ).getInt16(0, Endian.little);
      incline = inclineRaw * 0.1; // 0.1% resolution
      offset += 4; // inclination (2) + ramp angle (2)
    }

    // Bit 4 — Positive Elevation Gain (uint16)
    if ((flags & 0x10) != 0) {
      offset += 2;
    }

    // Bit 5 — Negative Elevation Gain (uint16)  — also carries pace in some profiles
    if ((flags & 0x20) != 0 && offset + 1 <= data.length) {
      // Some implementations put pace here; capture it opportunistically
      pace = data[offset].toDouble();
      offset += 2;
    }

    // Bit 6 — Instantaneous Pace (uint8, 1 s/km)
    if ((flags & 0x40) != 0 && offset + 1 <= data.length) {
      pace = data[offset].toDouble();
      offset += 1;
    }

    // Bit 7 — Average Pace (uint8)
    if ((flags & 0x80) != 0) {
      offset += 1;
    }

    // Bit 8 — Expended Energy (uint16 + uint16 + uint8 = 5 bytes)
    if ((flags & 0x100) != 0) {
      offset += 5;
    }

    // Bit 9 — Heart Rate (uint8)
    if ((flags & 0x200) != 0 && offset + 1 <= data.length) {
      heartRate = data[offset];
      offset += 1;
    }

    return DeviceDataSnapshot(
      speed: speed,
      cadenceOrPace: pace,
      controllableParam: incline,
      heartRate: heartRate,
    );
  }

  @override
  void dispose() {
    disconnect();
    _dataController.close();
    _connectionStateController.close();
  }
}
