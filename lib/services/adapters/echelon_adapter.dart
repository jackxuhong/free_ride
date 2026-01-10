import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/models/configuration_item.dart';

/// Echelon bike Bluetooth adapter
/// Implements proprietary Echelon protocol for direct bike connection
class EchelonAdapter implements DeviceAdapter {
  double _powerCalibration;
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _connectionStateSubscription;
  Timer? _pollTimer;
  bool _isReconnecting = false;
  bool _isConnected = false;
  bool _initDone = false;
  
  int _pollCounter = 1;
  int _currentResistance = 1;
  double? _currentCadence;
  double? _currentSpeed;
  double? _currentDistance;
  
  final StreamController<DeviceMetrics> _metricsController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  
  // Echelon UUIDs
  static const String serviceUuid = '0bf669f1-45f2-11e7-9598-0800200c9a66';
  static const String writeCharUuid = '0bf669f2-45f2-11e7-9598-0800200c9a66';
  static const String notifyCharUuid = '0bf669f4-45f2-11e7-9598-0800200c9a66';
  
  static const int maxResistance = 32;

  EchelonAdapter({double powerCalibration = 1.0}) : _powerCalibration = powerCalibration;

  @override
  DeviceType get deviceType => DeviceType.bike;

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

  @override
  Future<bool> connect(dynamic deviceInfo) async {
    try {
      // Extract address from SavedDevice
      String address;
      if (deviceInfo is SavedDevice) {
        address = deviceInfo.address;
      } else if (deviceInfo is BluetoothDevice) {
        _connectedDevice = deviceInfo;
        address = deviceInfo.remoteId.toString();
      } else {
        throw Exception('Invalid device info type');
      }

      if (_connectedDevice == null) {
        print('[Echelon] Scanning for device: $address');
        // MUST scan to get actual device object on iOS
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        
        await for (final scanResults in FlutterBluePlus.scanResults) {
          for (var result in scanResults) {
            if (result.device.remoteId.toString() == address) {
              print('[Echelon] Found device!');
              _connectedDevice = result.device;
              await FlutterBluePlus.stopScan();
              break;
            }
          }
          if (_connectedDevice != null) break;
        }

        if (_connectedDevice == null) {
          await FlutterBluePlus.stopScan();
          throw Exception('Device not found during scan');
        }
      }

      print('[Echelon] Connecting to device...');

      // Check if already connected
      final state = await _connectedDevice!.connectionState.first;
      if (state == BluetoothConnectionState.connected) {
        print('[Echelon] Already connected!');
      } else {
        // Connect with longer timeout
        print('[Echelon] Starting connection...');
        await _connectedDevice!.connect(timeout: const Duration(seconds: 30));
        print('[Echelon] Connected!');
      }
      
      print('[Echelon] Waiting for services to become available...');
      
      // Instead of calling discoverServices (which causes disconnect),
      // wait for services to be populated by iOS automatically
      await Future.delayed(const Duration(seconds: 2));
      
      // Check for services
      final services = _connectedDevice!.servicesList;
      print('[Echelon] Found ${services.length} services in list');
      
      if (services.isEmpty) {
        // If still no services, try discovery as last resort
        print('[Echelon] No services yet, requesting discovery...');
        try {
          await _connectedDevice!.discoverServices();
        } catch (e) {
          print('[Echelon] Discovery failed: $e');
          throw Exception('Failed to discover services. Device may need to be re-paired.');
        }
      }
      
      // Now find the Echelon service
      final echelonService = _connectedDevice!.servicesList.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
        orElse: () => throw Exception('Echelon service not found. Found services: ${_connectedDevice!.servicesList.map((s) => s.uuid).join(", ")}'),
      );
      
      print('[Echelon] Found Echelon service with ${echelonService.characteristics.length} characteristics');
      
      // Find write characteristic
      _writeCharacteristic = echelonService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == writeCharUuid.toLowerCase(),
        orElse: () => throw Exception('Write characteristic not found'),
      );
      
      // Find notify characteristic
      _notifyCharacteristic = echelonService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == notifyCharUuid.toLowerCase(),
        orElse: () => throw Exception('Notify characteristic not found'),
      );

      // Subscribe to notifications
      await _notifyCharacteristic!.setNotifyValue(true);
      
      _notificationSubscription = _notifyCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          _handleNotification(value);
        }
      });
      
      // Monitor connection state for auto-reconnection
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_isReconnecting) {
          _isConnected = false;
          _connectionStateController.add(false);
          _stopPolling();
          _attemptReconnect();
        }
      });
      
      // Initialize the device
      await _initializeDevice();
      
      // Start polling
      _startPolling();
      
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

  /// Initialize Echelon bike with required packet sequence
  Future<void> _initializeDevice() async {
    if (_writeCharacteristic == null) return;

    // Initialization sequence from Echelon protocol
    final initData1 = [0xf0, 0xa1, 0x00, 0x91];
    final initData2 = [0xf0, 0xa3, 0x00, 0x93];
    final initData3 = [0xf0, 0xb0, 0x01, 0x01, 0xa2];

    try {
      // Send init sequence
      await _writePacket(initData1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData2);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData1);
      await Future.delayed(const Duration(milliseconds: 100));
      await _writePacket(initData3);
      
      _initDone = true;
    } catch (e) {
      // Init failed
    }
  }

  /// Write packet to bike with checksum
  Future<void> _writePacket(List<int> data) async {
    if (_writeCharacteristic == null) return;
    
    try {
      await _writeCharacteristic!.write(data, withoutResponse: false);
    } catch (e) {
      // Write failed
    }
  }

  /// Start polling for status updates every 2 seconds
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _sendPoll();
    });
  }

  /// Stop polling timer
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Send poll packet to request status
  Future<void> _sendPoll() async {
    if (!_initDone || _writeCharacteristic == null) return;

    final packet = [0xf0, 0xa0, 0x01, _pollCounter, 0x00];
    
    // Calculate checksum (sum of first 4 bytes)
    int checksum = 0;
    for (int i = 0; i < 4; i++) {
      checksum += packet[i];
    }
    packet[4] = checksum & 0xFF;
    
    await _writePacket(packet);
    
    // Increment counter
    _pollCounter++;
    if (_pollCounter > 255) {
      _pollCounter = 1;
    }
  }

  @override
  Future<void> disconnect() async {
    _isReconnecting = false;
    _isConnected = false;
    _initDone = false;
    _connectionStateController.add(false);
    _stopPolling();
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
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
    if (!_initDone || _writeCharacteristic == null || !_isConnected) {
      return;
    }

    // Clamp level to valid range (1-32)
    final clampedLevel = level.clamp(1, maxResistance);
    
    final packet = [0xf0, 0xb1, 0x01, clampedLevel, 0x00];
    
    // Calculate checksum (sum of first 4 bytes)
    int checksum = 0;
    for (int i = 0; i < 4; i++) {
      checksum += packet[i];
    }
    packet[4] = checksum & 0xFF;
    
    await _writePacket(packet);
  }

  /// Handle notification data from bike
  void _handleNotification(List<int> data) {
    // Resistance update packet (5 bytes starting with 0xf0d2)
    if (data.length == 5 && data[0] == 0xf0 && data[1] == 0xd2) {
      _currentResistance = data[3];
      _emitMetrics();
      return;
    }

    // Main metrics packet (13 bytes starting with 0xf0d1)
    if (data.length == 13 && data[0] == 0xf0 && data[1] == 0xd1) {
      // Parse elapsed time (bytes 3-4)
      // final elapsedSeconds = (data[3] << 8) | data[4];
      
      // Parse distance (bytes 7-8) in 0.01 km resolution
      final distanceRaw = (data[7] << 8) | data[8];
      _currentDistance = distanceRaw / 100.0;
      
      // Parse cadence (byte 10)
      _currentCadence = data[10].toDouble();
      
      // Calculate speed from cadence (Echelon formula: speed = 0.37497622 * cadence)
      if (_currentCadence != null && _currentCadence! > 0) {
        _currentSpeed = 0.37497622 * _currentCadence!;
      } else {
        _currentSpeed = 0.0;
      }
      
      _emitMetrics();
    }
  }

  /// Emit current metrics
  void _emitMetrics() {
    final power = _calculatePower();
    
    _metricsController.add(DeviceMetrics(
      cadence: _currentCadence,
      speed: _currentSpeed,
      distance: _currentDistance,
      power: power,
      resistance: _currentResistance,
    ));
  }

  /// Calculate power from cadence and resistance using simplified formula
  /// Based on polynomial approximation from Echelon watt tables
  int? _calculatePower() {
    if (_currentCadence == null || _currentCadence! <= 0 || _currentResistance <= 0) {
      return null;
    }

    final cadence = _currentCadence!;
    final resistance = _currentResistance;
    
    // Simplified polynomial power formula
    // Power increases with both cadence and resistance
    // Base formula: power ≈ a*cadence² + b*resistance*cadence + c*resistance²
    final a = 0.015; // Cadence squared coefficient
    final b = 0.8;   // Cadence-resistance interaction coefficient
    final c = 0.5;   // Resistance squared coefficient
    
    final basePower = (a * cadence * cadence) + 
                      (b * resistance * cadence) + 
                      (c * resistance * resistance);
    
    // Apply calibration and return
    return (basePower * _powerCalibration).round();
  }

  @override
  Future<void> setIncline(double level) async {
    // Echelon bikes do not support incline control
    // Silently ignore this command
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
      'maxResistance': ConfigurationItem(
        key: 'maxResistance',
        name: 'Max Resistance Level',
        description: 'Maximum resistance level for this bike',
        dataType: ConfigurationDataType.integer,
        defaultValue: maxResistance,
        sortOrder: 4,
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
      'maxResistance': maxResistance,
    };
  }

  @override
  void dispose() {
    disconnect();
    _metricsController.close();
    _connectionStateController.close();
  }
}
