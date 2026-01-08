import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';

/// Manages Bluetooth connections to Echelon Connect Sport devices
class EchelonConnectionManager {
  // Echelon Connect Sport UUIDs (from C++ implementation)
  static const String echelonServiceUuid = '0bf669f1-45f2-11e7-9598-0800200c9a66';
  // Note: Specific characteristic UUIDs need to be determined from device discovery
  // For now, we'll discover characteristics dynamically

  final FitnessDevice device;
  final DeviceType deviceType;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionStateSubscription;
  bool _isReconnecting = false;
  bool _isConnected = false;

  // Device capabilities (Echelon Connect Sport supports resistance 1-32)
  int _minResistance = 1;
  int _maxResistance = 32;

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

  /// Data characteristic for reading data
  BluetoothCharacteristic? get dataCharacteristic => _dataCharacteristic;

  /// Control characteristic for sending commands
  BluetoothCharacteristic? get controlCharacteristic => _controlCharacteristic;

  EchelonConnectionManager({
    required this.device,
  }) : deviceType = device.deviceType;

  /// Connect to the device
  Future<bool> connect() async {
    try {
      if (device.deviceAddress == null) {
        return false;
      }

      // Get all connected and available devices
      final connectedDevices = FlutterBluePlus.connectedDevices;
      _connectedDevice = connectedDevices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () => BluetoothDevice(remoteId: DeviceIdentifier(device.deviceAddress!)),
      );

      // Check current connection state
      final connectionState = await _connectedDevice!.connectionState.first;

      // Connect if not already connected
      if (connectionState != BluetoothConnectionState.connected) {
        await _connectedDevice!.connect();
      }

      // Discover services
      await _discoverServices();

      // Set up notifications for data characteristic
      if (_dataCharacteristic != null) {
        await _dataCharacteristic!.setNotifyValue(true);
        _dataSubscription = _dataCharacteristic!.lastValueStream.listen((value) {
          _dataStreamController.add(value);
        });
      }

      // Set up connection state monitoring
      _connectionStateSubscription = _connectedDevice!.connectionState.listen((state) {
        _isConnected = state == BluetoothConnectionState.connected;
        _connectionStateController.add(_isConnected);

        if (!_isConnected && !_isReconnecting) {
          _handleDisconnection();
        }
      });

      _isConnected = true;
      _connectionStateController.add(true);
      return true;
    } catch (e) {
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Discover Echelon services and characteristics
  Future<void> _discoverServices() async {
    final services = await _connectedDevice!.discoverServices();

    for (final service in services) {
      if (service.uuid.toString().toLowerCase() == echelonServiceUuid.toLowerCase()) {
        // Found Echelon service, discover characteristics
        for (final characteristic in service.characteristics) {
          final uuid = characteristic.uuid.toString().toLowerCase();

          // Echelon uses specific characteristics for data and control
          // We'll identify them by their properties
          if (characteristic.properties.notify) {
            _dataCharacteristic = characteristic;
          } else if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            _controlCharacteristic = characteristic;
          }
        }
        break;
      }
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _connectedDevice?.disconnect();
    _isConnected = false;
    _connectionStateController.add(false);
  }

  /// Handle disconnection and attempt reconnection
  void _handleDisconnection() {
    if (_isReconnecting) return;

    _isReconnecting = true;

    // Simple reconnection logic - in production, add exponential backoff
    Future.delayed(const Duration(seconds: 2), () async {
      _isReconnecting = false;
      if (!_isConnected && device.deviceAddress != null) {
        await connect();
      }
    });
  }

  /// Dispose resources
  void dispose() {
    _dataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _dataStreamController.close();
    _connectionStateController.close();
  }
}