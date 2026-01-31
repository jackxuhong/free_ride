import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart' as model;
import 'package:free_ride/services/fitness_device.dart';
import 'package:free_ride/services/echelon_power_table.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// Echelon indoor bike implementation
/// Supports Echelon Connect Sport and similar models using proprietary protocol
class EchelonDevice implements FitnessDevice {
  final model.FTMSDevice device;
  
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notify1Characteristic;
  BluetoothCharacteristic? _notify2Characteristic;
  StreamSubscription? _notify1Subscription;
  StreamSubscription? _notify2Subscription;
  StreamSubscription? _connectionStateSubscription;
  Timer? _pollTimer;
  bool _isConnected = false;
  
  // Echelon-specific UUIDs
  static const String echelonServiceUuid = '0bf669f1-45f2-11e7-9598-0800200c9a66';
  static const String echelonWriteUuid = '0bf669f2-45f2-11e7-9598-0800200c9a66';
  static const String echelonNotify1Uuid = '0bf669f3-45f2-11e7-9598-0800200c9a66';
  static const String echelonNotify2Uuid = '0bf669f4-45f2-11e7-9598-0800200c9a66';
  
  // Device state
  double _currentCadence = 0.0;
  double _currentSpeed = 0.0;
  double _currentPower = 0.0;
  int _currentResistance = 1;
  int _echelonResistance = 1; // Native Echelon resistance (1-32)
  
  // Polling counter for keep-alive packets
  int _pollCounter = 1;
  
  final StreamController<bool> _connectionStateController = StreamController.broadcast();
  DeviceDataSnapshot? _lastSnapshot;
  
  @override
  Stream<bool> get connectionState => _connectionStateController.stream;
  
  @override
  bool get isConnected => _isConnected;
  
  @override
  model.DeviceType get deviceType => model.DeviceType.indoorBike;
  
  // Echelon native range is 1-32, we map to FTMS standard 1-20
  @override
  int get minResistance => 1;
  
  @override
  int get maxResistance => 20;
  
  @override
  double get minIncline => 0.0;
  
  @override
  double get maxIncline => 0.0; // Bikes don't have incline
  
  EchelonDevice(this.device);
  
  /// Detects if a Bluetooth device is an Echelon bike
  /// Returns FTMSDevice model if supported, null otherwise
  /// 
  /// Note: Unlike FTMS detection, this does NOT connect to the device.
  /// Echelon bikes have known capabilities (resistance 1-32, indoor bike type),
  /// so we only verify the device name. Actual connection happens when starting a ride.
  static Future<model.FTMSDevice?> detectDevice(BluetoothDevice bleDevice) async {
    // Check if device name starts with "ECH"
    if (!bleDevice.platformName.startsWith('ECH')) {
      return null;
    }
    
    developer.log('Echelon bike detected: ${bleDevice.platformName}');
    
    // Create and return device model immediately
    // No connection needed - all Echelon capabilities are known
    return model.FTMSDevice(
      id: bleDevice.remoteId.toString(),
      name: bleDevice.platformName,
      deviceType: model.DeviceType.indoorBike,
      isVirtual: false,
      deviceAddress: bleDevice.remoteId.toString(),
    );
  }
  
  @override
  Future<bool> connect() async {
    try {
      developer.log('Connecting to Echelon device: ${device.name}');
      
      // Find the device
      final devices = FlutterBluePlus.connectedDevices;
      _connectedDevice = devices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () => throw Exception('Device not found in connected devices'),
      );
      
      // If not already connected, connect
      if (_connectedDevice!.isDisconnected) {
        await _connectedDevice!.connect(timeout: const Duration(seconds: 10));
      }
      
      // Discover services
      final services = await _connectedDevice!.discoverServices();
      final echelonService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == echelonServiceUuid.toLowerCase(),
      );
      
      // Get characteristics
      _writeCharacteristic = echelonService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == echelonWriteUuid.toLowerCase(),
      );
      _notify1Characteristic = echelonService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == echelonNotify1Uuid.toLowerCase(),
      );
      _notify2Characteristic = echelonService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == echelonNotify2Uuid.toLowerCase(),
      );
      
      // Subscribe to notifications
      await _notify1Characteristic!.setNotifyValue(true);
      await _notify2Characteristic!.setNotifyValue(true);
      
      _notify1Subscription = _notify1Characteristic!.lastValueStream.listen(_onNotification);
      _notify2Subscription = _notify2Characteristic!.lastValueStream.listen(_onNotification);
      
      // Monitor connection state
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        final connected = state == BluetoothConnectionState.connected;
        if (_isConnected != connected) {
          _isConnected = connected;
          _connectionStateController.add(connected);
          
          if (!connected) {
            developer.log('Echelon device disconnected');
            _stopPolling();
          }
        }
      });
      
      // Send initialization sequence
      await _initialize();
      
      // Start polling timer (keep-alive every 2 seconds)
      _startPolling();
      
      _isConnected = true;
      _connectionStateController.add(true);
      
      developer.log('Successfully connected to Echelon device');
      return true;
    } catch (e) {
      developer.log('Failed to connect to Echelon device: $e');
      await disconnect();
      return false;
    }
  }
  
  @override
  Future<void> disconnect() async {
    try {
      developer.log('Disconnecting from Echelon device');
      
      _stopPolling();
      
      await _notify1Subscription?.cancel();
      await _notify2Subscription?.cancel();
      await _connectionStateSubscription?.cancel();
      
      _notify1Subscription = null;
      _notify2Subscription = null;
      _connectionStateSubscription = null;
      
      if (_connectedDevice != null && _connectedDevice!.isConnected) {
        await _connectedDevice!.disconnect();
      }
      
      _isConnected = false;
      _connectionStateController.add(false);
      
      developer.log('Disconnected from Echelon device');
    } catch (e) {
      developer.log('Error disconnecting from Echelon device: $e');
    }
  }
  
  /// Sends initialization sequence to Echelon bike
  Future<void> _initialize() async {
    developer.log('Initializing Echelon device');
    
    final initData1 = Uint8List.fromList([0xF0, 0xA1, 0x00, 0x91]);
    final initData2 = Uint8List.fromList([0xF0, 0xA3, 0x00, 0x93]);
    final initData3 = Uint8List.fromList([0xF0, 0xB0, 0x01, 0x01, 0xA2]);
    
    // Send initialization sequence as per reference code
    for (int i = 0; i < 4; i++) {
      await _writeCharacteristic!.write(initData1, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    await _writeCharacteristic!.write(initData2, withoutResponse: false);
    await Future.delayed(const Duration(milliseconds: 50));
    
    await _writeCharacteristic!.write(initData1, withoutResponse: false);
    await Future.delayed(const Duration(milliseconds: 50));
    
    await _writeCharacteristic!.write(initData3, withoutResponse: false);
    
    developer.log('Echelon device initialized');
  }
  
  /// Starts polling timer for keep-alive packets
  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendPoll();
    });
  }
  
  /// Stops polling timer
  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
  
  /// Sends keep-alive poll packet
  Future<void> _sendPoll() async {
    if (_writeCharacteristic == null || !_isConnected) {
      return;
    }
    
    try {
      final pollData = Uint8List.fromList([0xF0, 0xA0, 0x01, _pollCounter, 0x00]);
      
      // Calculate checksum (sum of first 4 bytes)
      int checksum = 0;
      for (int i = 0; i < 4; i++) {
        checksum += pollData[i];
      }
      pollData[4] = checksum & 0xFF;
      
      await _writeCharacteristic!.write(pollData, withoutResponse: false);
      
      _pollCounter++;
      if (_pollCounter > 255) {
        _pollCounter = 1;
      }
    } catch (e) {
      developer.log('Error sending poll: $e');
    }
  }
  
  /// Handles notification data from Echelon bike
  void _onNotification(List<int> data) {
    if (data.isEmpty) {
      return;
    }
    
    try {
      // Check packet type by header
      if (data.length == 5 && data[0] == 0xF0 && data[1] == 0xD2) {
        // Resistance feedback packet
        _parseResistancePacket(data);
      } else if (data.length == 13 && data[0] == 0xF0 && data[1] == 0xD1) {
        // Data packet with cadence
        _parseDataPacket(data);
      }
    } catch (e) {
      developer.log('Error parsing Echelon notification: $e');
    }
  }
  
  /// Parses 5-byte resistance feedback packet
  void _parseResistancePacket(List<int> data) {
    _echelonResistance = data[3];
    _currentResistance = _mapEchelonToFtms(_echelonResistance);
    
    developer.log('Echelon resistance updated: $_echelonResistance (FTMS: $_currentResistance)');
  }
  
  /// Parses 13-byte data packet with cadence and distance
  void _parseDataPacket(List<int> data) {
    // Byte 10: Cadence (RPM)
    _currentCadence = data[10].toDouble();
    
    // Calculate speed from cadence: speed (km/h) = cadence (RPM) × 0.375
    _currentSpeed = _currentCadence * 0.375;
    
    // Calculate power from cadence and resistance using lookup table
    _currentPower = EchelonPowerTable.calculatePower(
      cadence: _currentCadence,
      resistance: _echelonResistance,
    );
    
    // Optional: Extract distance for validation (bytes 7-8, meters × 100)
    // final distanceValue = (data[7] << 8) | data[8];
    // final distanceMeters = distanceValue / 100.0;
  }
  
  /// Maps Echelon resistance (1-32) to FTMS range (1-20)
  int _mapEchelonToFtms(int echelonResistance) {
    if (echelonResistance <= 1) return 1;
    if (echelonResistance >= 32) return 20;
    
    // Linear mapping: (echelon - 1) / 31 * 19 + 1
    final normalized = (echelonResistance - 1) / 31.0;
    return (normalized * 19.0 + 1.0).round();
  }
  
  /// Maps FTMS resistance (1-20) to Echelon range (1-32)
  int _mapFtmsToEchelon(int ftmsResistance) {
    if (ftmsResistance <= 1) return 1;
    if (ftmsResistance >= 20) return 32;
    
    // Linear mapping: (ftms - 1) / 19 * 31 + 1
    final normalized = (ftmsResistance - 1) / 19.0;
    return (normalized * 31.0 + 1.0).round();
  }
  
  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // For real devices, return the last received data
    _lastSnapshot = DeviceDataSnapshot(
      speed: _currentSpeed,
      power: _currentPower,
      cadenceOrPace: _currentCadence,
      heartRate: null, // Echelon doesn't provide heart rate
      controllableParam: _currentResistance.toDouble(),
    );
    
    return _lastSnapshot!;
  }
  
  @override
  Future<bool> sendControlCommand(ControlCommand command) async {
    if (_writeCharacteristic == null || !_isConnected) {
      return false;
    }
    
    try {
      if (command is SetResistance) {
        // Map FTMS resistance (1-20) to Echelon resistance (1-32)
        final ftmsLevel = command.level.round().clamp(1, 20);
        final echelonLevel = _mapFtmsToEchelon(ftmsLevel);
        
        // Format: [0xF0, 0xB1, 0x01, resistance, checksum]
        final resistanceCmd = Uint8List.fromList([0xF0, 0xB1, 0x01, echelonLevel, 0x00]);
        
        // Calculate checksum (sum of first 4 bytes)
        int checksum = 0;
        for (int i = 0; i < 4; i++) {
          checksum += resistanceCmd[i];
        }
        resistanceCmd[4] = checksum & 0xFF;
        
        await _writeCharacteristic!.write(resistanceCmd, withoutResponse: false);
        
        developer.log('Sent resistance command: FTMS $ftmsLevel -> Echelon $echelonLevel');
        return true;
      } else if (command is SetIncline) {
        // Bikes don't support incline, ignore
        developer.log('Ignoring incline command for bike');
        return false;
      }
    } catch (e) {
      developer.log('Error sending control command: $e');
      return false;
    }
    
    return false;
  }
  
  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    // Not applicable for real devices
  }
  
  @override
  Uint8List getFTMSDataPacket() {
    // Not applicable for real devices
    return Uint8List(0);
  }
  
  @override
  void dispose() {
    disconnect();
    _connectionStateController.close();
  }
}
