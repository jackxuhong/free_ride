import 'dart:async';
import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/ftms_command_sender.dart';
import 'package:free_ride/services/ftms_connection_manager.dart';
import 'package:free_ride/services/ftms_data_parser.dart';
import 'package:free_ride/services/ftms_device_discovery.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// FTMS Bluetooth service for real fitness equipment
/// This is a stub implementation - full Bluetooth integration to be completed
class FTMSService extends VirtualFitnessDevice {
  final FitnessDevice device;
  final DeviceType _deviceType;

  late final FTMSConnectionManager _connectionManager;
  late final FTMSCommandSender _commandSender;

  final StreamController<DeviceDataSnapshot> _dataController = StreamController.broadcast();
  DeviceDataSnapshot? _lastSnapshot;

  /// Stream of connection state (true = connected, false = disconnected)
  Stream<bool> get connectionState => _connectionManager.connectionState;

  /// Current connection state
  bool get isConnected => _connectionManager.isConnected;

  /// Device resistance range
  int get minResistance => _connectionManager.minResistance;
  int get maxResistance => _connectionManager.maxResistance;

  /// Device incline range
  double get minIncline => _connectionManager.minIncline;
  double get maxIncline => _connectionManager.maxIncline;

  FTMSService({required this.device}) : _deviceType = device.deviceType {
    _connectionManager = FTMSConnectionManager(device: device);
    _commandSender = FTMSCommandSender(
      controlCharacteristic: null, // Will be set after connection
      minResistance: _connectionManager.minResistance,
      maxResistance: _connectionManager.maxResistance,
    );

    // Listen to raw data and parse it
    _connectionManager.dataStream.listen((rawData) {
      final snapshot = _deviceType == DeviceType.indoorBike
          ? FTMSDataParser.parseIndoorBikeData(rawData)
          : FTMSDataParser.parseTreadmillData(rawData);
      _lastSnapshot = snapshot;
      _dataController.add(snapshot);
    });
  }

  @override
  DeviceType get deviceType => _deviceType;

  /// Scan for FTMS devices
  static Future<List<Map<String, dynamic>>> scanForDevices() async {
    final discovery = FTMSDeviceDiscovery();
    return await discovery.scanForDevices();
  }

  /// Connect to the device
  Future<bool> connect() async {
    print('FTMSService: Starting connection to ${device.name}');
    final success = await _connectionManager.connect();
    print('FTMSService: Connection result: $success');
    if (success) {
      // Update command sender with the control characteristic
      _commandSender = FTMSCommandSender(
        controlCharacteristic: _connectionManager.controlCharacteristic,
        minResistance: _connectionManager.minResistance,
        maxResistance: _connectionManager.maxResistance,
      );
      print('FTMSService: Command sender updated with characteristics');
    } else {
      print('FTMSService: Connection failed');
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
