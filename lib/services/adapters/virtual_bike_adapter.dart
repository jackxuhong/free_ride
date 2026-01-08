import 'dart:async';
import 'package:free_ride/services/device_adapter.dart';

/// Virtual bike adapter for testing without real hardware
class VirtualBikeAdapter implements DeviceAdapter {
  final String deviceId;
  double _speed = 30.0; // km/h - using this as the "calibration" value
  double _currentResistance = 1.0;
  
  final _metricsController = StreamController<DeviceMetrics>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  Timer? _updateTimer;
  bool _isConnected = false;

  VirtualBikeAdapter({required this.deviceId, double speed = 30.0}) : _speed = speed;

  @override
  DeviceType get deviceType => DeviceType.bike;

  @override
  Stream<DeviceMetrics> get metricsStream => _metricsController.stream;

  @override
  Stream<bool> get connectionStateStream => _connectionController.stream;

  @override
  double get powerCalibration => _speed;

  @override
  set powerCalibration(double value) {
    _speed = value.clamp(0.0, 300.0);
  }

  @override
  bool get isConnected => _isConnected;

  @override
  Future<bool> connect(dynamic device) async {
    if (_isConnected) return true;
    
    _isConnected = true;
    _connectionController.add(true);
    
    // Start generating metrics
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isConnected) return;
      
      // Calculate metrics based on speed and resistance
      final cadence = (_speed / 0.37).clamp(0.0, 200.0); // Reverse of speed calculation
      final power = (_speed * _currentResistance * 2.5).round(); // Approximate power
      
      _metricsController.add(DeviceMetrics(
        cadence: cadence,
        speed: _speed,
        power: power,
        resistance: _currentResistance.round(),
        distance: null,
        heartRate: null,
      ));
    });
    
    return true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }
  }

  @override
  Future<void> setResistance(int level) async {
    _currentResistance = level.toDouble().clamp(1.0, 32.0);
  }

  void dispose() {
    _updateTimer?.cancel();
    _metricsController.close();
    _connectionController.close();
  }
}
