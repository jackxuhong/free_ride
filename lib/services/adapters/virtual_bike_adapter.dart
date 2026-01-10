import 'dart:async';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/configuration_item.dart';

/// Virtual bike adapter for testing and simulation
class VirtualBikeAdapter implements DeviceAdapter {
  final String deviceId;
  double _powerCalibration;
  double _targetSpeed;
  int _minResistance;
  int _maxResistance;
  
  bool _isConnected = false;
  Timer? _simulationTimer;
  double _currentSpeed = 0.0;
  double _currentCadence = 0.0;
  int _currentResistance = 1;
  double _totalDistance = 0.0;
  
  final StreamController<DeviceMetrics> _metricsController = StreamController.broadcast();
  final StreamController<bool> _connectionStateController = StreamController.broadcast();

  VirtualBikeAdapter({
    required this.deviceId,
    double speed = 0.0,
    double powerCalibration = 1.0,
  })  : _targetSpeed = speed,
        _powerCalibration = powerCalibration,
        _minResistance = 1,
        _maxResistance = 32;

  @override
  DeviceType get deviceType => DeviceType.bike;

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
    _currentCadence = 0.0;
  }

  @override
  Future<void> setResistance(int level) async {
    final clamped = level.clamp(_minResistance, _maxResistance);
    _currentResistance = clamped;
  }

  @override
  Future<void> setIncline(double level) async {
    // Virtual bikes don't support incline
  }

  void _startSimulation() {
    _simulationTimer = Timer.periodic(Duration(milliseconds: 1000), (_) {
      _updateSimulation();
    });
  }

  void _updateSimulation() {
    // Gradually approach target speed
    if (_currentSpeed < _targetSpeed) {
      _currentSpeed = (_currentSpeed + 5.0).clamp(0.0, _targetSpeed);
    } else if (_currentSpeed > _targetSpeed) {
      _currentSpeed = (_currentSpeed - 5.0).clamp(_targetSpeed, double.maxFinite);
    }

    // Simulate cadence based on speed and resistance
    _currentCadence = (_currentSpeed * 2 + (_currentResistance * 0.5)).clamp(0.0, 120.0);

    // Simulate power output
    final power = ((_currentSpeed * _currentSpeed * 2.0) + 
                  (_currentResistance * _currentSpeed * 3.0)) * _powerCalibration;

    // Update distance
    _totalDistance += (_currentSpeed / 3600.0); // km

    final metrics = DeviceMetrics(
      speed: _currentSpeed,
      cadence: _currentCadence,
      power: power.toInt(),
      resistance: _currentResistance,
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
        description: 'Simulated cycling speed',
        dataType: ConfigurationDataType.floatingPoint,
        minValue: 0.0,
        maxValue: 200.0,
        defaultValue: 0.0,
        sortOrder: 2,
        units: 'km/h',
      ),
      'minResistance': ConfigurationItem(
        key: 'minResistance',
        name: 'Minimum Resistance',
        description: 'Minimum resistance level',
        dataType: ConfigurationDataType.integer,
        minValue: 1,
        maxValue: 16,
        defaultValue: 1,
        sortOrder: 3,
      ),
      'maxResistance': ConfigurationItem(
        key: 'maxResistance',
        name: 'Maximum Resistance',
        description: 'Maximum resistance level',
        dataType: ConfigurationDataType.integer,
        minValue: 16,
        maxValue: 32,
        defaultValue: 32,
        sortOrder: 4,
      ),
      'deviceType': ConfigurationItem(
        key: 'deviceType',
        name: 'Device Type',
        description: 'Type of virtual bike',
        dataType: ConfigurationDataType.string,
        defaultValue: 'Virtual Bike',
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
    if (config.containsKey('minResistance')) {
      final value = config['minResistance'];
      if (value is int) {
        _minResistance = value;
      }
    }
    if (config.containsKey('maxResistance')) {
      final value = config['maxResistance'];
      if (value is int) {
        _maxResistance = value;
        // Re-clamp current resistance if needed
        _currentResistance = _currentResistance.clamp(_minResistance, _maxResistance);
      }
    }
  }

  @override
  Map<String, dynamic> getCurrentConfiguration() {
    return {
      'powerCoefficient': _powerCalibration,
      'targetSpeed': _targetSpeed,
      'minResistance': _minResistance,
      'maxResistance': _maxResistance,
      'deviceType': 'Virtual Bike',
    };
  }

  @override
  void dispose() {
    disconnect();
    _metricsController.close();
    _connectionStateController.close();
  }
}
