import 'dart:async';
import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/echelon_command_sender.dart';
import 'package:free_ride/services/echelon_connection_manager.dart';
import 'package:free_ride/services/echelon_data_parser.dart';
import 'package:free_ride/services/unified_device_discovery.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// Echelon Bluetooth service for Echelon Connect Sport devices
class EchelonService extends VirtualFitnessDevice {
  final FitnessDevice device;
  final DeviceType _deviceType;

  late final EchelonConnectionManager _connectionManager;
  late final EchelonCommandSender _commandSender;

  final StreamController<DeviceDataSnapshot> _dataController = StreamController.broadcast();
  DeviceDataSnapshot? _lastSnapshot;

  /// Stream of connection state (true = connected, false = disconnected)
  Stream<bool> get connectionState => _connectionManager.connectionState;

  /// Current connection state
  bool get isConnected => _connectionManager.isConnected;

  /// Device resistance range
  int get minResistance => _connectionManager.minResistance;
  int get maxResistance => _connectionManager.maxResistance;

  EchelonService({required this.device}) : _deviceType = device.deviceType {
    _connectionManager = EchelonConnectionManager(device: device);
    _commandSender = EchelonCommandSender(
      controlCharacteristic: null, // Will be set after connection
      minResistance: _connectionManager.minResistance,
      maxResistance: _connectionManager.maxResistance,
    );

    // Listen to raw data and parse it
    _connectionManager.dataStream.listen((rawData) {
      final snapshot = EchelonDataParser.parseData(rawData);
      _lastSnapshot = snapshot;
      _dataController.add(snapshot);
    });
  }

  @override
  DeviceType get deviceType => _deviceType;

  /// Scan for Echelon devices
  static Future<List<Map<String, dynamic>>> scanForDevices() async {
    // Use unified discovery instead
    final discovery = UnifiedDeviceDiscovery();
    final allDevices = await discovery.scanForDevices();
    return allDevices.where((device) =>
      UnifiedDeviceDiscovery.getDeviceProtocol(device) == 'echelon'
    ).toList();
  }

  /// Connect to the device
  Future<bool> connect() async {
    final success = await _connectionManager.connect();
    if (success) {
      // Update command sender with the control characteristic
      _commandSender = EchelonCommandSender(
        controlCharacteristic: _connectionManager.controlCharacteristic,
        minResistance: _connectionManager.minResistance,
        maxResistance: _connectionManager.maxResistance,
      );
    }
    return success;
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await _connectionManager.disconnect();
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
    return await _commandSender.sendControlCommand(command);
  }

  @override
  Uint8List getFTMSDataPacket() {
    // Real devices don't generate packets - they receive them
    return Uint8List(0);
  }

  @override
  void dispose() {
    _connectionManager.dispose();
    _dataController.close();
  }
}