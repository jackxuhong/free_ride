import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/models/configuration_item.dart';

/// FTMS (Fitness Machine Service) Bluetooth adapter
/// Supports both bikes and treadmills with standard FTMS protocol
class FTMSAdapter implements DeviceAdapter {
  final DeviceType _deviceType;
  double _powerCalibration;
  
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
  
  final StreamController<DeviceMetrics> _metricsController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  
  // FTMS UUIDs
  static const String ftmsServiceUuid = '00001826-0000-1000-8000-00805f9b34fb';
  static const String indoorBikeDataUuid = '00002ad2-0000-1000-8000-00805f9b34fb';
  static const String treadmillDataUuid = '00002acd-0000-1000-8000-00805f9b34fb';
  static const String controlPointUuid = '00002ad9-0000-1000-8000-00805f9b34fb';
  static const String resistanceRangeUuid = '00002ad6-0000-1000-8000-00805f9b34fb';
  static const String inclineRangeUuid = '00002ad5-0000-1000-8000-00805f9b34fb';
  static const String featureUuid = '00002acc-0000-1000-8000-00805f9b34fb';

  FTMSAdapter({
    required DeviceType deviceType,
    double powerCalibration = 1.0,
  })  : _deviceType = deviceType,
        _powerCalibration = powerCalibration;

  @override
  DeviceType get deviceType => _deviceType;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Stream<DeviceMetrics> get metricsStream => _metricsController.stream;

  @override
  double get powerCalibration => _powerCalibration;

  @override
  set powerCalibration(double value) {
    _powerCalibration = value;
  }

  /// Device resistance range (bikes only)
  int get minResistance => _minResistance;
  int get maxResistance => _maxResistance;

  /// Device incline range (treadmills only)
  double get minIncline => _minIncline;
  double get maxIncline => _maxIncline;

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

  @override
  Future<bool> connect(dynamic deviceInfo) async {
    try {
      // Extract BluetoothDevice from SavedDevice
      BluetoothDevice device;
      if (deviceInfo is SavedDevice) {
        // Create device from address and connect directly
        device = BluetoothDevice(remoteId: DeviceIdentifier(deviceInfo.address));
        print('[FTMS] Connecting to device: ${deviceInfo.address}');
      } else if (deviceInfo is BluetoothDevice) {
        device = deviceInfo;
      } else {
        throw Exception('Invalid device info type');
      }
      
      _connectedDevice = device;

      // Check current connection state
      final connectionState = await _connectedDevice!.connectionState.first;
      
      // Connect if not already connected
      if (connectionState == BluetoothConnectionState.disconnected) {
        await _connectedDevice!.connect(timeout: const Duration(seconds: 15));
      }

      // Discover services
      final services = await _connectedDevice!.discoverServices();
      
      // Find FTMS service
      final ftmsService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(ftmsServiceUuid),
        orElse: () => throw Exception('FTMS service not found'),
      );
      
      // Read device capabilities
      await _readDeviceCapabilities(ftmsService);

      // Find the appropriate data characteristic
      final dataCharUuid = _deviceType == DeviceType.bike 
          ? indoorBikeDataUuid 
          : treadmillDataUuid;
      
      _dataCharacteristic = ftmsService.characteristics.firstWhere(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(dataCharUuid),
        orElse: () => throw Exception('Data characteristic not found'),
      );
      
      // Find and cache control point characteristic
      await _setupControlPoint(ftmsService);

      // Subscribe to data notifications
      await _dataCharacteristic!.setNotifyValue(true);
      
      _dataSubscription = _dataCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          final metrics = _deviceType == DeviceType.bike
              ? _parseIndoorBikeData(value)
              : _parseTreadmillData(value);
          _metricsController.add(metrics);
        }
      });
      
      // Monitor connection state for auto-reconnection
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_isReconnecting) {
          _isConnected = false;
          _connectionStateController.add(false);
          _attemptReconnect();
        }
      });
      
      _isConnected = true;
      _connectionStateController.add(true);

      return true;
    } catch (e) {
      await disconnect();
      
      // Trigger auto-reconnect for initial connection failures
      if (!_isReconnecting) {
        _attemptReconnect();
      }
      
      return false;
    }
  }

  /// Read device capabilities (resistance/incline ranges)
  Future<void> _readDeviceCapabilities(BluetoothService ftmsService) async {
    if (_deviceType == DeviceType.bike) {
      // Read fitness machine features (silently)
      try {
        final featureChar = ftmsService.characteristics.firstWhere(
          (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(featureUuid),
        );
        await featureChar.read();
      } catch (e) {
        // Features not available
      }
      
      // Read resistance range
      try {
        final resistanceRangeChar = ftmsService.characteristics.firstWhere(
          (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(resistanceRangeUuid),
        );
        final value = await resistanceRangeChar.read();
        if (value.length >= 6) {
          _minResistance = ByteData.sublistView(Uint8List.fromList(value.sublist(0, 2))).getInt16(0, Endian.little);
          _maxResistance = ByteData.sublistView(Uint8List.fromList(value.sublist(2, 4))).getInt16(0, Endian.little);
        }
      } catch (e) {
        // Use defaults
      }
    } else if (_deviceType == DeviceType.treadmill) {
      // Read incline range
      try {
        final inclineRangeChar = ftmsService.characteristics.firstWhere(
          (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(inclineRangeUuid),
        );
        final value = await inclineRangeChar.read();
        if (value.length >= 6) {
          _minIncline = ByteData.sublistView(Uint8List.fromList(value.sublist(0, 2))).getInt16(0, Endian.little) / 10.0;
          _maxIncline = ByteData.sublistView(Uint8List.fromList(value.sublist(2, 4))).getInt16(0, Endian.little) / 10.0;
        }
      } catch (e) {
        // Use defaults
      }
    }
  }

  /// Setup control point characteristic for sending commands
  Future<void> _setupControlPoint(BluetoothService ftmsService) async {
    try {
      _controlCharacteristic = ftmsService.characteristics.firstWhere(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(controlPointUuid),
      );
      
      // Subscribe to control point notifications
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
  }

  @override
  Future<void> disconnect() async {
    _isReconnecting = false;
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
    if (_isReconnecting || _connectedDevice == null) return;
    _isReconnecting = true;
    
    await Future.delayed(const Duration(seconds: 2));
    
    if (!_isReconnecting) return;
    
    final success = await connect(_connectedDevice!);
    _isReconnecting = !success;
  }

  @override
  Future<void> setResistance(int level) async {
    if (_controlCharacteristic == null || !_isConnected) {
      return;
    }

    try {
      if (_deviceType == DeviceType.bike) {
        // Use simulation parameters for bikes (opcode 0x11)
        final gradePercent = ((level - _minResistance - (_maxResistance - _minResistance) * 0.25) * 20.0 / (_maxResistance - _minResistance)).clamp(-5.0, 15.0);
        final windSpeed = 0;
        final grade = (gradePercent * 100).round();
        final crr = 40; // Rolling resistance coefficient
        final windResistance = 40; // Wind resistance coefficient
        
        final packet = [
          0x11, // Set Indoor Bike Simulation Parameters
          windSpeed & 0xFF, (windSpeed >> 8) & 0xFF,
          grade & 0xFF, (grade >> 8) & 0xFF,
          crr,
          windResistance,
        ];
        
        await _controlCharacteristic!.write(packet, withoutResponse: false);
      } else if (_deviceType == DeviceType.treadmill) {
        // Use target inclination for treadmills (opcode 0x06)
        final inclineValue = (level * 10).clamp((_minIncline * 10).round(), (_maxIncline * 10).round());
        
        final packet = [
          0x06,
          inclineValue & 0xFF,
          (inclineValue >> 8) & 0xFF,
        ];
        
        await _controlCharacteristic!.write(packet, withoutResponse: false);
      }
    } catch (e) {
      // Failed to send command
    }
  }

  @override
  Future<void> setIncline(double level) async {
    if (_controlCharacteristic == null || !_isConnected || _deviceType != DeviceType.treadmill) {
      return;
    }

    try {
      // Use target inclination for treadmills (opcode 0x06)
      final inclineValue = (level * 10).clamp((_minIncline * 10).round(), (_maxIncline * 10).round()).round();
      
      final packet = [
        0x06,
        inclineValue & 0xFF,
        (inclineValue >> 8) & 0xFF,
      ];
      
      await _controlCharacteristic!.write(packet, withoutResponse: false);
    } catch (e) {
      // Failed to send command
    }
  }

  /// Parse Indoor Bike Data (UUID 0x2AD2)
  DeviceMetrics _parseIndoorBikeData(List<int> data) {
    if (data.length < 4) return DeviceMetrics();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    double? cadence;
    int? power;
    int? heartRate;
    int? resistance;

    // Speed (bit 0 always present)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01;
      offset += 2;
    }

    // Cadence (bit 2)
    if ((flags & 0x04) != 0 && offset + 2 <= data.length) {
      final cadenceRaw = data[offset] | (data[offset + 1] << 8);
      cadence = cadenceRaw * 0.5;
      offset += 2;
    }

    // Power (bit 6)
    if ((flags & 0x40) != 0 && offset + 2 <= data.length) {
      final powerRaw = data[offset] | (data[offset + 1] << 8);
      power = (powerRaw * _powerCalibration).round();
      offset += 2;
    }

    // Resistance (bit 5)
    if ((flags & 0x20) != 0 && offset + 2 <= data.length) {
      final resistanceRaw = data[offset] | (data[offset + 1] << 8);
      resistance = resistanceRaw;
      offset += 2;
    }

    // Heart Rate (bit 9)
    if ((flags & 0x100) != 0 && offset + 1 <= data.length) {
      heartRate = data[offset];
    }

    return DeviceMetrics(
      speed: speed,
      power: power,
      cadence: cadence,
      heartRate: heartRate,
      resistance: resistance,
    );
  }

  /// Parse Treadmill Data (UUID 0x2ACD)
  DeviceMetrics _parseTreadmillData(List<int> data) {
    if (data.length < 4) return DeviceMetrics();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    int? heartRate;

    // Speed (bit 0 always present)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01;
      offset += 2;
    }

    // Skip pace if present (bit 5)
    if ((flags & 0x20) != 0 && offset + 1 <= data.length) {
      offset += 1;
    }

    // Skip incline (bit 3)
    if ((flags & 0x08) != 0 && offset + 2 <= data.length) {
      offset += 2;
    }

    // Heart Rate (bit 8)
    if ((flags & 0x100) != 0 && offset + 1 <= data.length) {
      heartRate = data[offset];
    }

    return DeviceMetrics(
      speed: speed,
      heartRate: heartRate,
    );
  }

  @override
  Map<String, ConfigurationItem> getConfigurationSchema() {
    return {
      'powerCoefficient': ConfigurationItem(
        key: 'powerCoefficient',
        name: 'Power Coefficient',
        description: 'Calibration multiplier for power readings',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: 0.5,
        maxValue: 2.0,
        defaultValue: 1.0,
        sortOrder: 1,
        units: 'x',
      ),
      'deviceAddress': ConfigurationItem(
        key: 'deviceAddress',
        name: 'Device Address',
        description: 'Bluetooth device MAC address',
        dataType: ConfigurationDataType.string,
        defaultValue: _connectedDevice?.remoteId.str ?? 'Unknown',
        sortOrder: 2,
        isReadOnly: true,
      ),
      'deviceName': ConfigurationItem(
        key: 'deviceName',
        name: 'Device Name',
        description: 'Manufacturer device name',
        dataType: ConfigurationDataType.string,
        defaultValue: _connectedDevice?.platformName ?? 'Unknown',
        sortOrder: 3,
        isReadOnly: true,
      ),
    };
  }

  @override
  void applyConfiguration(Map<String, dynamic> config) {
    if (config.containsKey('powerCoefficient')) {
      final value = config['powerCoefficient'];
      if (value is num) {
        _powerCalibration = value.toDouble();
      }
    }
  }

  @override
  Map<String, dynamic> getCurrentConfiguration() {
    return {
      'powerCoefficient': _powerCalibration,
      'deviceAddress': _connectedDevice?.remoteId.str ?? 'Unknown',
      'deviceName': _connectedDevice?.platformName ?? 'Unknown',
    };
  }

  @override
  void dispose() {
    disconnect();
    _metricsController.close();
    _connectionStateController.close();
  }
}
