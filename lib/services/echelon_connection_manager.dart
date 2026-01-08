import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/fitness_device.dart';

/// Manages Bluetooth connections to Echelon Connect Sport devices
class EchelonConnectionManager {
  // Echelon Connect Sport UUIDs (from C++ implementation)
  static const String echelonServiceUuid = '0bf669f1-45f2-11e7-9598-0800200c9a66';
  static const String echelonWriteCharacteristicUuid = '0bf669f2-45f2-11e7-9598-0800200c9a66';
  static const String echelonNotify1CharacteristicUuid = '0bf669f3-45f2-11e7-9598-0800200c9a66';
  static const String echelonNotify2CharacteristicUuid = '0bf669f4-45f2-11e7-9598-0800200c9a66';

  final FitnessDevice device;
  final DeviceType deviceType;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionStateSubscription;
  Timer? _pollTimer;
  int _pollCounter = 1;
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
        print('EchelonConnectionManager: No device address available');
        return false;
      }

      print('EchelonConnectionManager: Connecting to device ${device.name} at ${device.deviceAddress}');

      // Get all connected and available devices
      final connectedDevices = FlutterBluePlus.connectedDevices;
      print('EchelonConnectionManager: Found ${connectedDevices.length} already connected devices');
      _connectedDevice = connectedDevices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () {
          print('EchelonConnectionManager: Creating new BluetoothDevice for ${device.deviceAddress}');
          return BluetoothDevice(remoteId: DeviceIdentifier(device.deviceAddress!));
        },
      );

      // Check current connection state
      final connectionState = await _connectedDevice!.connectionState.first;
      print('EchelonConnectionManager: Current connection state: $connectionState');

      // Connect if not already connected
      if (connectionState != BluetoothConnectionState.connected) {
        print('EchelonConnectionManager: Starting connection with 30s timeout...');
        // Use extended timeout and connection parameters for fitness devices
        final connectFuture = _connectedDevice!.connect(
          timeout: const Duration(seconds: 30), // Extended timeout for fitness devices
          autoConnect: false, // Manual connection control
        );

        // Also implement manual timeout as backup
        final timeoutFuture = Future.delayed(const Duration(seconds: 35), () {
          throw TimeoutException('Connection timeout after 35 seconds');
        });

        try {
          await Future.any([connectFuture, timeoutFuture]);
          print('EchelonConnectionManager: Connection completed successfully');
        } catch (e) {
          print('EchelonConnectionManager: Connection failed with error: $e');
          rethrow;
        }
      } else {
        print('EchelonConnectionManager: Device already connected');
      }

      // Discover services
      print('Discovering services...');
      await _discoverServices();
      print('Service discovery complete');

      // Send initialization commands
      if (_controlCharacteristic != null) {
        print('Sending initialization commands...');
        await _sendInitCommands();
        print('Initialization complete');

        // Start polling timer (every 2 seconds as per C++ implementation)
        _startPolling();
      }

      // Set up notifications for data characteristic
      if (_dataCharacteristic != null) {
        print('Setting up data notifications...');
        await _dataCharacteristic!.setNotifyValue(true);
        _dataSubscription = _dataCharacteristic!.lastValueStream.listen((value) {
          _dataStreamController.add(value);
        });
        print('Data notifications set up');
      } else {
        print('Warning: No data characteristic found');
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
      print('Failed to connect to Echelon device: $e');
      _isConnected = false;
      _connectionStateController.add(false);
      return false;
    }
  }

  /// Discover Echelon services and characteristics
  Future<void> _discoverServices() async {
    final services = await _connectedDevice!.discoverServices();
    print('Found ${services.length} services');

    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      print('Service: $serviceUuid');

      if (serviceUuid == echelonServiceUuid.toLowerCase()) {
        print('Found Echelon service! Discovering characteristics...');
        // Found Echelon service, discover characteristics
        for (final characteristic in service.characteristics) {
          final charUuid = characteristic.uuid.toString().toLowerCase();
          print('  Characteristic: $charUuid (notify: ${characteristic.properties.notify}, write: ${characteristic.properties.write})');

          // Echelon uses specific characteristic UUIDs
          if (charUuid == echelonWriteCharacteristicUuid.toLowerCase()) {
            _controlCharacteristic = characteristic;
            print('  -> Selected as CONTROL characteristic');
          } else if (charUuid == echelonNotify1CharacteristicUuid.toLowerCase() ||
                     charUuid == echelonNotify2CharacteristicUuid.toLowerCase()) {
            // Use the first notify characteristic we find for data
            if (_dataCharacteristic == null) {
              _dataCharacteristic = characteristic;
              print('  -> Selected as DATA characteristic');
            }
          }
        }
        break;
      }
    }

    if (_dataCharacteristic == null) {
      print('Warning: No data characteristic found in Echelon service');
    }
    if (_controlCharacteristic == null) {
      print('Warning: No control characteristic found in Echelon service');
    }
  }

  /// Send initialization commands to the Echelon device
  /// Based on the C++ implementation btinit() method
  Future<void> _sendInitCommands() async {
    if (_controlCharacteristic == null) return;

    try {
      // Initialization sequence from C++ code
      final initData1 = [0xf0, 0xa1, 0x00, 0x91];
      final initData2 = [0xf0, 0xa3, 0x00, 0x93];
      final initData3 = [0xf0, 0xa4, 0x00, 0x94];

      // Send initData1 four times
      for (int i = 0; i < 4; i++) {
        await _controlCharacteristic!.write(initData1);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Send initData2
      await _controlCharacteristic!.write(initData2);
      await Future.delayed(const Duration(milliseconds: 100));

      // Send initData1 again
      await _controlCharacteristic!.write(initData1);
      await Future.delayed(const Duration(milliseconds: 100));

      // Send initData3
      await _controlCharacteristic!.write(initData3);
      await Future.delayed(const Duration(milliseconds: 100));

      print('Echelon initialization commands sent successfully');
    } catch (e) {
      print('Failed to send initialization commands: $e');
    }
  }

  /// Start polling timer to request data from device
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _sendPollCommand();
    });
  }

  /// Send poll command to request data from device
  void _sendPollCommand() {
    if (_controlCharacteristic == null) return;

    try {
      // Poll command format: [0xf0, 0xa0, 0x01, counter, checksum]
      final command = Uint8List(5);
      command[0] = 0xf0; // Header
      command[1] = 0xa0; // Poll command
      command[2] = 0x01; // Subcommand
      command[3] = _pollCounter & 0xFF; // Counter

      // Calculate checksum
      command[4] = (command[0] + command[1] + command[2] + command[3]) & 0xFF;

      _controlCharacteristic!.write(command);

      _pollCounter++;
      if (_pollCounter > 255) {
        _pollCounter = 1; // Reset counter when it overflows
      }
    } catch (e) {
      print('Failed to send poll command: $e');
    }
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
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

    // Wait longer before attempting reconnection for fitness devices
    Future.delayed(const Duration(seconds: 5), () async {
      _isReconnecting = false;
      if (!_isConnected && device.deviceAddress != null) {
        print('Attempting to reconnect to Echelon device...');
        final success = await connect();
        if (!success) {
          print('Reconnection failed, will retry in 10 seconds...');
          // If reconnection fails, wait longer before next attempt
          Future.delayed(const Duration(seconds: 10), () {
            if (!_isConnected) {
              _handleDisconnection(); // Try again
            }
          });
        }
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