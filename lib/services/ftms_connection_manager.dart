import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';

/// Manages Bluetooth connections to FTMS devices
class FTMSConnectionManager {
  // FTMS UUIDs
  static const String ftmsServiceUuid = '00001826-0000-1000-8000-00805f9b34fb';
  static const String indoorBikeDataUuid = '00002ad2-0000-1000-8000-00805f9b34fb';
  static const String treadmillDataUuid = '00002acd-0000-1000-8000-00805f9b34fb';
  static const String controlPointUuid = '00002ad9-0000-1000-8000-00805f9b34fb';
  static const String resistanceRangeUuid = '00002ad6-0000-1000-8000-00805f9b34fb';
  static const String inclineRangeUuid = '00002ad5-0000-1000-8000-00805f9b34fb';
  static const String featureUuid = '00002acc-0000-1000-8000-00805f9b34fb';

  final FitnessDevice device;
  final DeviceType deviceType;

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

  final StreamController<List<int>> _dataStreamController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();

  /// Stream of raw data packets from the device
  Stream<List<int>> get dataStream => _dataStreamController.stream;

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

  /// Data characteristic for reading data
  BluetoothCharacteristic? get dataCharacteristic => _dataCharacteristic;

  /// Control characteristic for sending commands
  BluetoothCharacteristic? get controlCharacteristic => _controlCharacteristic;

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

  FTMSConnectionManager({
    required this.device,
  }) : deviceType = device.deviceType;

  /// Connect to the device
  Future<bool> connect() async {
    try {
      if (device.deviceAddress == null) {
        // print('Cannot connect: device address is null');
        return false;
      }

      // print('Attempting to connect to device: ${device.name}');

      // Get all connected and available devices
      final connectedDevices = FlutterBluePlus.connectedDevices;
      _connectedDevice = connectedDevices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () => BluetoothDevice(remoteId: DeviceIdentifier(device.deviceAddress!)),
      );

      // Check current connection state
      final connectionState = await _connectedDevice!.connectionState.first;
      // print('Current connection state: $connectionState');

      // Connect if not already connected
      if (connectionState == BluetoothConnectionState.disconnected) {
        // print('Connecting to device...');
        await _connectedDevice!.connect(timeout: const Duration(seconds: 15));
        // print('Connected successfully');
      } else {
        // print('Device already connected');
      }

      // Discover services
      // print('Discovering services...');
      final services = await _connectedDevice!.discoverServices();
      // print('Found ${services.length} services');

      // Find FTMS service
      final ftmsService = services.firstWhere(
        (s) => _normalizeUuid(s.uuid.toString()) == _normalizeUuid(ftmsServiceUuid),
        orElse: () => throw Exception('FTMS service not found'),
      );
      // print('Found FTMS service with ${ftmsService.characteristics.length} characteristics');

      // Read device capabilities for bikes
      if (deviceType == DeviceType.indoorBike) {
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
      if (deviceType == DeviceType.treadmill) {
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
      final dataCharUuid = deviceType == DeviceType.indoorBike
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
          _dataStreamController.add(value);
        }
      });

      // Monitor connection state for auto-reconnection
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_isReconnecting) {
          _isConnected = false;
          _connectionStateController.add(false);
          // print('FTMS device disconnected, attempting to reconnect...');
          _attemptReconnect();
        }
      });

      _isConnected = true;
      _connectionStateController.add(true);

      return true;
    } catch (e) {
      // print('Error connecting to device: $e');
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
      // print('Successfully reconnected to FTMS device');
      _isReconnecting = false;
    } else {
      // print('Reconnection failed, will retry...');
      _isReconnecting = false;
      // Will trigger again via connection state listener
    }
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
    _dataStreamController.close();
    _connectionStateController.close();
  }
}