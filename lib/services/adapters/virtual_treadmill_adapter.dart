import 'dart:async';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/configuration_item.dart';

/// Virtual treadmill adapter for testing and simulation
class VirtualTreadmillAdapter implements DeviceAdapter {
  final String deviceId;
  double _powerCalibration;
  double _targetSpeed;
  double _minIncline;
  double _maxIncline;
  
  bool _isConnected = false;
  Timer? _simulationTimer;
  double _currentSpeed = 0.0;
  double _currentIncline = 0.0;
  double _totalDistance = 0.0;
  
  final StreamController<DeviceMetrics> _metricsController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();

  VirtualTreadmillAdapter({
    required this.deviceId,
    double speed = 0.0,
    double powerCalibration = 1.0,
  })  : _targetSpeed = speed,
        _powerCalibration = powerCalibration,
        _minIncline = -5.0,
        _maxIncline = 15.0;

  @override
  DeviceType get deviceType => DeviceType.treadmill;

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
    _isConnected = true;
    _connectionStateController.add(true);
    _startSimulation();
    return true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionStateController.add(false);
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _currentSpeed = 0.0;
    _currentIncline = 0.0;
  }

  @override
  Future<void> setResistance(int level) async {
    // Virtual treadmills don't have resistance
  }

  @override
  Future<void> setIncline(double level) async {
    final clamped = level.clamp(_minIncline, _maxIncline);
    _currentIncline = clamped;
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(Duration(milliseconds: 1000), (_) {
      _updateSimulation();
    });
  }

  void _updateSimulation() {
    // Gradually approach target speed
    if (_currentSpeed < _targetSpeed) {
      _currentSpeed = (_currentSpeed + 2.0).clamp(0.0, _targetSpeed);
    } else if (_currentSpeed > _targetSpeed) {
      _currentSpeed = (_currentSpeed - 2.0).clamp(_targetSpeed, double.maxFinite);
    }

    // Simulate power output based on speed and incline
    final basePower = _currentSpeed * _currentSpeed * 2.5;
    final inclineFactor = 1.0 + (_currentIncline * 0.05);
    final power = (basePower * inclineFactor) * _powerCalibration;

    // Update distance
    _totalDistance += (_currentSpeed / 3600.0); // km

    final metrics = DeviceMetrics(
      speed: _currentSpeed,
      power: power.toInt(),
      distance: _totalDistance,
    );

    if (!_metricsController.isClosed) {
      _metricsController.add(metrics);
    }
  }

  @override
  Map<String, ConfigurationItem> getConfigurationSchema() {
    return {
      'powerCoefficient': ConfigurationItem(
        key: 'powerCoefficient',
        name: 'Power Coefficient',
        description: 'Calibration multiplier for power simulation',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: 0.5,
        maxValue: 2.0,
        defaultValue: 1.0,
        sortOrder: 1,
        units: 'x',
      ),
      'targetSpeed': ConfigurationItem(
        key: 'targetSpeed',
        name: 'Target Speed',
        description: 'Simulated running speed',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: 0.0,
        maxValue: 200.0,
        defaultValue: 0.0,
        sortOrder: 2,
        units: 'km/h',
      ),
      'minIncline': ConfigurationItem(
        key: 'minIncline',
        name: 'Minimum Incline',
        description: 'Minimum incline percentage',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: -5.0,
        maxValue: 0.0,
        defaultValue: -5.0,
        sortOrder: 3,
        units: '%',
      ),
      'maxIncline': ConfigurationItem(
        key: 'maxIncline',
        name: 'Maximum Incline',
        description: 'Maximum incline percentage',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: 0.0,
        maxValue: 15.0,
        defaultValue: 15.0,
        sortOrder: 4,
        units: '%',
      ),
      'deviceType': ConfigurationItem(
        key: 'deviceType',
        name: 'Device Type',
        description: 'Type of virtual treadmill',
        dataType: ConfigurationDataType.string,
        defaultValue: 'Virtual Treadmill',
        sortOrder: 5,
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
    if (config.containsKey('targetSpeed')) {
      final value = config['targetSpeed'];
      if (value is num) {
        _targetSpeed = value.toDouble();
      }
    }
    if (config.containsKey('minIncline')) {
      final value = config['minIncline'];
      if (value is num) {
        _minIncline = value.toDouble();
      }
    }
    if (config.containsKey('maxIncline')) {
      final value = config['maxIncline'];
      if (value is num) {
        _maxIncline = value.toDouble();
        // Re-clamp current incline if needed
        _currentIncline = _currentIncline.clamp(_minIncline, _maxIncline);
      }
    }
  }

  @override
  Map<String, dynamic> getCurrentConfiguration() {
    return {
      'powerCoefficient': _powerCalibration,
      'targetSpeed': _targetSpeed,
      'minIncline': _minIncline,
      'maxIncline': _maxIncline,
      'deviceType': 'Virtual Treadmill',
    };
  }

  @override
  void dispose() {
    disconnect();
    _metricsController.close();
    _connectionStateController.close();
  }
}
