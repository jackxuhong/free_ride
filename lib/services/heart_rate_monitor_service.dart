import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/ftms_device.dart' as model;

/// BLE Heart Rate Monitor service.
///
/// Connects to standard GATT Heart Rate Service (0x180D) devices
/// and streams heart rate values from the Heart Rate Measurement
/// characteristic (0x2A37).
class HeartRateMonitorService {
  final model.FTMSDevice device;

  BluetoothDevice? _connectedDevice;
  StreamSubscription? _dataSubscription;
  StreamSubscription? _connectionStateSubscription;
  bool _isReconnecting = false;
  bool _isConnected = false;
  int _currentHeartRate = 0;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  final StreamController<int> _heartRateController =
      StreamController<int>.broadcast();

  // Standard GATT UUIDs
  static const String heartRateServiceUuid =
      '0000180d-0000-1000-8000-00805f9b34fb';
  static const String heartRateMeasurementUuid =
      '00002a37-0000-1000-8000-00805f9b34fb';
  static const String bodySensorLocationUuid =
      '00002a38-0000-1000-8000-00805f9b34fb';

  HeartRateMonitorService(this.device);

  bool get isConnected => _isConnected;
  int get currentHeartRate => _currentHeartRate;
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<int> get heartRateStream => _heartRateController.stream;

  /// Normalize UUID to short form for comparison.
  static String _normalizeUuid(String uuid) {
    final cleaned = uuid.toLowerCase().replaceAll('-', '');
    if (cleaned.length == 32 &&
        cleaned.startsWith('0000') &&
        cleaned.endsWith('00805f9b34fb')) {
      return cleaned.substring(4, 8);
    }
    if (cleaned.length == 4) return cleaned;
    return cleaned;
  }

  /// Detect if a BLE device is a Heart Rate Monitor.
  ///
  /// Looks for the standard GATT Heart Rate Service (0x180D) and the
  /// Heart Rate Measurement characteristic (0x2A37).
  static Future<model.FTMSDevice?> detectDevice(
    BluetoothDevice bleDevice,
  ) async {
    if (bleDevice.platformName.isEmpty) return null;

    try {
      await bleDevice.connect(timeout: const Duration(seconds: 5));
      final services = await bleDevice.discoverServices();

      BluetoothService? hrService;
      for (final s in services) {
        if (_normalizeUuid(s.uuid.toString()) ==
            _normalizeUuid(heartRateServiceUuid)) {
          hrService = s;
          break;
        }
      }

      await bleDevice.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));

      if (hrService == null) return null;

      // Verify the measurement characteristic exists
      final hasMeasurement = hrService.characteristics.any(
        (c) =>
            _normalizeUuid(c.uuid.toString()) ==
            _normalizeUuid(heartRateMeasurementUuid),
      );

      if (!hasMeasurement) return null;

      return model.FTMSDevice(
        id: bleDevice.remoteId.str,
        name: bleDevice.platformName.isNotEmpty
            ? bleDevice.platformName
            : 'HR Monitor',
        deviceType: model.DeviceType.heartRateMonitor,
        isVirtual: false,
        deviceAddress: bleDevice.remoteId.str,
        lastConnected: DateTime.now(),
      );
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
        try {
          await bleDevice.disconnect();
        } catch (_) {}
        rethrow;
      }
      try {
        await bleDevice.disconnect();
      } catch (_) {}
      return null;
    }
  }

  /// Connect and subscribe to heart rate notifications.
  Future<bool> connect() async {
    try {
      if (device.deviceAddress == null) return false;

      developer.log(
        'Connecting to HR monitor: ${device.name}',
        name: 'HRMonitor',
      );

      final connectedDevices = FlutterBluePlus.connectedDevices;
      _connectedDevice = connectedDevices.firstWhere(
        (d) => d.remoteId.toString() == device.deviceAddress,
        orElse: () =>
            BluetoothDevice(remoteId: DeviceIdentifier(device.deviceAddress!)),
      );

      final state = await _connectedDevice!.connectionState.first;
      if (state == BluetoothConnectionState.disconnected) {
        await _connectedDevice!.connect(
          timeout: const Duration(seconds: 15),
        );
      }

      final services = await _connectedDevice!.discoverServices();
      final hrService = services.firstWhere(
        (s) =>
            _normalizeUuid(s.uuid.toString()) ==
            _normalizeUuid(heartRateServiceUuid),
        orElse: () => throw Exception('Heart Rate service not found'),
      );

      final measurementChar = hrService.characteristics.firstWhere(
        (c) =>
            _normalizeUuid(c.uuid.toString()) ==
            _normalizeUuid(heartRateMeasurementUuid),
        orElse: () =>
            throw Exception('Heart Rate Measurement characteristic not found'),
      );

      await measurementChar.setNotifyValue(true);
      _dataSubscription = measurementChar.lastValueStream.listen((value) {
        if (value.isNotEmpty) {
          final hr = parseHeartRate(value);
          if (hr > 0) {
            _currentHeartRate = hr;
            _heartRateController.add(hr);
          }
        }
      });

      _connectionStateSubscription =
          _connectedDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            !_isReconnecting) {
          _isConnected = false;
          _connectionStateController.add(false);
          developer.log(
            'HR monitor disconnected, attempting reconnect...',
            name: 'HRMonitor',
            level: 900,
          );
          _attemptReconnect();
        }
      });

      _isConnected = true;
      _connectionStateController.add(true);
      developer.log('HR monitor connected', name: 'HRMonitor');
      return true;
    } catch (e) {
      developer.log(
        'Error connecting to HR monitor: $e',
        name: 'HRMonitor',
        level: 1000,
        error: e,
      );
      await disconnect(preserveReconnectState: _isReconnecting);
      if (!_isReconnecting) _attemptReconnect();
      return false;
    }
  }

  /// Disconnect from the device.
  ///
  /// When [preserveReconnectState] is `true` the reconnect flag is left
  /// untouched so that a retry loop in [_attemptReconnect] can continue.
  Future<void> disconnect({bool preserveReconnectState = false}) async {
    if (!preserveReconnectState) {
      _isReconnecting = false;
    }
    _isConnected = false;
    _currentHeartRate = 0;
    _connectionStateController.add(false);
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
  }

  /// Attempt to reconnect with exponential backoff.
  ///
  /// Retries up to 5 times (2s, 4s, 8s, 16s, 16s). Stops immediately if
  /// [_isReconnecting] is set to `false` externally.
  Future<void> _attemptReconnect() async {
    if (_isReconnecting) return;
    _isReconnecting = true;

    const maxAttempts = 5;
    var delay = const Duration(seconds: 2);

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      await Future.delayed(delay);
      if (!_isReconnecting) return;

      developer.log(
        'HR monitor reconnect attempt $attempt/$maxAttempts...',
        name: 'HRMonitor',
        level: 800,
      );

      final success = await connect();
      if (success) {
        developer.log('HR monitor reconnected', name: 'HRMonitor', level: 800);
        _isReconnecting = false;
        return;
      }

      if (!_isReconnecting) return;

      delay = Duration(seconds: (delay.inSeconds * 2).clamp(2, 16));
    }

    developer.log(
      'HR monitor reconnection failed after $maxAttempts attempts',
      name: 'HRMonitor',
      level: 1000,
    );
    _isReconnecting = false;
  }

  /// Parse the Heart Rate Measurement characteristic value.
  ///
  /// Per the Bluetooth GATT specification:
  /// - Byte 0: Flags (bit 0 = HR format: 0 → UINT8, 1 → UINT16)
  /// - Byte 1 (or 1-2): Heart rate value
  static int parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;

    final flags = data[0];
    final isUint16 = (flags & 0x01) != 0;

    if (isUint16) {
      if (data.length < 3) return 0;
      return data[1] | (data[2] << 8);
    } else {
      if (data.length < 2) return 0;
      return data[1];
    }
  }

  /// Release resources.
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _heartRateController.close();
  }
}
