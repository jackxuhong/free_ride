import 'dart:async';
import 'package:free_ride/services/device_adapter.dart';

/// Virtual treadmill adapter for testing without real hardware
class VirtualTreadmillAdapter implements DeviceAdapter {
  final String deviceId;
  double _speed = 15.0; // km/h - using this as the "calibration" value
  double _currentIncline = 0.0;
  
  final _metricsController = StreamController<DeviceMetrics>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  
  Timer? _updateTimer;
  bool _isConnected = false;

  VirtualTreadmillAdapter({required this.deviceId, double speed = 15.0}) : _speed = speed;

  @override
  DeviceType get deviceType => DeviceType.treadmill;

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
      
      // Calculate metrics based on speed and incline
      final adjustedSpeed = _speed * (1.0 - (_currentIncline * 0.02)); // Slower on incline
      final pace = adjustedSpeed > 0 ? 60.0 / adjustedSpeed : 0.0; // min/km
      final power = (adjustedSpeed * (1.0 + (_currentIncline * 0.1)) * 50).round(); // Approximate power
      
      _metricsController.add(DeviceMetrics(
        cadence: pace.toDouble(), // Using cadence field for pace
        speed: adjustedSpeed,
        power: power,
        resistance: _currentIncline.round(),
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
    // For treadmill, resistance = incline
    _currentIncline = level.toDouble().clamp(0.0, 15.0);
  }

  void dispose() {
    _updateTimer?.cancel();
    _metricsController.close();
    _connectionController.close();
  }
}
