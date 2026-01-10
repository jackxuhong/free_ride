import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/models/configuration_item.dart';

/// Heart Rate Monitor Bluetooth adapter
/// Supports standard Bluetooth Heart Rate Service (0x180D)
class HeartRateAdapter implements DeviceAdapter {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _heartRateCharacteristic;
  StreamSubscription? _heartRateSubscription;
  StreamSubscription? _connectionStateSubscription;
  bool _isReconnecting = false;
  bool _isConnected = false;
  
  final StreamController<DeviceMetrics> _metricsController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  
  // Heart Rate Service UUIDs
  static const String heartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String heartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  HeartRateAdapter();

  @override
  DeviceType get deviceType => DeviceType.indoorBike;

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionStateStream => _connectionStateController.stream;

  @override
  Stream<DeviceMetrics> get metricsStream => _metricsController.stream;

  @override
  double get powerCalibration => 1.0;

  @override
  set powerCalibration(double value) {
    // Heart rate monitors don't use power calibration
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

  @override
  Future<bool> connect(dynamic deviceInfo) async {
    try {
      // Extract BluetoothDevice from SavedDevice
      BluetoothDevice device;
      if (deviceInfo is SavedDevice) {
        // Create device from address and connect directly
        device = BluetoothDevice(remoteId: DeviceIdentifier(deviceInfo.address));
        print('[HR] Connecting to device: ${deviceInfo.address}');
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
      
      // Find Heart Rate service
      final hrService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(heartRateServiceUuid),
        orElse: () => throw Exception('Heart Rate service not found'),
      );
      
      // Find heart rate measurement characteristic
      _heartRateCharacteristic = hrService.characteristics.firstWhere(
        (c) => _normalizeUuid(c.uuid.toString()) == _normalizeUuid(heartRateMeasurementUuid),
        orElse: () => throw Exception('Heart Rate measurement characteristic not found'),
      );

      // Subscribe to heart rate notifications
      await _heartRateCharacteristic!.setNotifyValue(true);
      
      _heartRateSubscription = _heartRateCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          final heartRate = _parseHeartRateMeasurement(value);
          if (heartRate != null) {
            _metricsController.add(DeviceMetrics(heartRate: heartRate));
          }
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

  @override
  Future<void> disconnect() async {
    _isReconnecting = false;
    _isConnected = false;
    _connectionStateController.add(false);
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    await _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
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
    // Heart rate monitors don't support resistance control
  }

  /// Parse Heart Rate Measurement characteristic value
  /// Format defined in Bluetooth Heart Rate Service specification
  int? _parseHeartRateMeasurement(List<int> data) {
    if (data.isEmpty) return null;

    final flags = data[0];
    
    // Bit 0: Heart Rate Value Format (0 = uint8, 1 = uint16)
    final isUint16 = (flags & 0x01) != 0;
    
    if (isUint16) {
      // uint16 format
      if (data.length < 3) return null;
      return data[1] | (data[2] << 8);
    } else {
      // uint8 format
      if (data.length < 2) return null;
      return data[1];
    }
  }

  @override
  Future<void> setIncline(double level) async {
    // Heart rate monitors don't support incline
  }

  @override
  Map<String, ConfigurationItem> getConfigurationSchema() {
    return {
      'deviceAddress': ConfigurationItem(
        key: 'deviceAddress',
        name: 'Device Address',
        description: 'Bluetooth device MAC address',
        dataType: ConfigurationDataType.string,
        defaultValue: _connectedDevice?.remoteId.str ?? 'Unknown',
        sortOrder: 1,
        isReadOnly: true,
      ),
      'deviceName': ConfigurationItem(
        key: 'deviceName',
        name: 'Device Name',
        description: 'Manufacturer device name',
        dataType: ConfigurationDataType.string,
        defaultValue: _connectedDevice?.platformName ?? 'Unknown',
        sortOrder: 2,
        isReadOnly: true,
      ),
    };
  }

  @override
  void applyConfiguration(Map<String, dynamic> config) {
    // Heart rate adapters have no configurable options
  }

  @override
  Map<String, dynamic> getCurrentConfiguration() {
    return {
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
