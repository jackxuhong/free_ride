import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/models/ride_summary.dart';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/services/ride_calculator.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/services/profile_service.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/utils/constants.dart';

enum RideStatus { notStarted, running, paused, completed, cancelled }

class RideProvider with ChangeNotifier {
  SavedRoute? _route;
  RideStatus _status = RideStatus.notStarted;
  Timer? _simulationTimer;

  // Position and progress
  int _currentSegmentIndex = 0;
  double _progressInSegment = 0.0; // 0.0 to 1.0
  LatLng? _currentPosition;
  double _currentBearing = 0.0; // Direction of travel in degrees

  // Time tracking
  DateTime? _startTime;
  DateTime? _endTime;
  Duration _totalDuration = Duration.zero;
  Duration _movingTime = Duration.zero;
  Duration _pausedTime = Duration.zero;
  DateTime? _pauseStartTime;

  // Distance tracking
  double _completedDistance = 0.0;

  // Speed tracking
  double _currentSpeed = 0.0;
  double _maxSpeed = 0.0;
  double _minSpeed = double.infinity;
  List<double> _speedSamples = [];

  // Elevation tracking
  double _currentElevation = 0.0;
  double _currentGrade = 0.0;
  double _maxGrade = double.negativeInfinity;
  double _minGrade = double.infinity;

  // Power tracking
  List<PowerSample> _powerSamples = [];

  // Device tracking
  VirtualFitnessDevice? _activeDevice;
  DeviceAdapter? _activeAdapter; // Keep reference to the actual adapter for connect/disconnect
  double _currentCadence = 0.0;
  double _currentHeartRate = 0.0;
  List<double> _cadenceSamples = [];
  List<double> _heartRateSamples = [];
  double _workoutIntensity = 1.0;
  StreamSubscription? _deviceConnectionSubscription;
  
  // Real-time calories tracking
  double _currentCalories = 0.0;
  double _totalElevationGained = 0.0;
  double _cachedBodyWeight = 70.0; // Cached from profile, default 70kg

  // Summary caching
  RideSummary? _lastSummary;
  Uint8List? _routeThumbnail;

  // Getters
  RideStatus get status => _status;
  LatLng? get currentPosition => _currentPosition;
  double get currentBearing => _currentBearing;
  double get currentSpeed => _currentSpeed;
  double get currentElevation => _currentElevation;
  double get currentGrade => _currentGrade * 100; // Return as percentage
  double get completedDistance => _completedDistance;
  double get completionPercentage {
    if (_route == null) return 0;
    return (_completedDistance / _route!.geometry.totalDistance * 100)
        .clamp(0, 100);
  }

  Duration get totalDuration => _totalDuration;
  Duration get movingTime => _movingTime;
  DateTime? get startTime => _startTime;
  double get currentCadence => _currentCadence;
  double get currentHeartRate => _currentHeartRate;
  double get workoutIntensity => _workoutIntensity;
  VirtualFitnessDevice? get activeDevice => _activeDevice;
  double get currentCalories => _currentCalories;

  /// Initialize ride with a route
  void initializeRide(SavedRoute route, {Uint8List? thumbnail}) async {
    _route = route;
    _status = RideStatus.notStarted;
    _routeThumbnail = thumbnail;
    _resetMetrics();
    
    // Load user profile weight for calorie calculations
    final profile = await ProfileService().getProfile();
    _cachedBodyWeight = profile?.bodyWeight ?? 70.0;
    
    // Set initial position
    _currentPosition = route.coordinates.start;
    _currentElevation = route.elevationProfile.elevations.first;
    
    notifyListeners();
  }



  /// Initialize ride with a DeviceAdapter (new architecture)
  Future<void> initializeRideWithAdapter(
    SavedRoute route,
    DeviceAdapter adapter,
    SavedDevice device,
  ) async {
    _route = route;
    _status = RideStatus.notStarted;
    _routeThumbnail = _generateSimpleThumbnail(route); // Generate basic thumbnail
    _resetMetrics();
    
    // Load user profile weight for calorie calculations
    final profile = await ProfileService().getProfile();
    _cachedBodyWeight = profile?.bodyWeight ?? 70.0;
    
    // Store the adapter reference
    _activeAdapter = adapter;
    
    // Create a wrapper for the DeviceAdapter that implements VirtualFitnessDevice interface
    _activeDevice = _DeviceAdapterWrapper(adapter, device);
    _workoutIntensity = 1.0;
    
    // Set initial position
    _currentPosition = route.coordinates.start;
    _currentElevation = route.elevationProfile.elevations.first;
    
    // Start the ride automatically
    await startRide();
    
    notifyListeners();
  }

  /// Set workout intensity multiplier (0.5 to 2.0)
  void setWorkoutIntensity(double intensity) {
    _workoutIntensity = intensity.clamp(0.5, 2.0);
    notifyListeners();
  }

  /// Start the ride simulation
  Future<void> startRide() async {
    if (_route == null || _status == RideStatus.running) return;

    if (_status == RideStatus.notStarted) {
      _startTime = DateTime.now();
    }

    _status = RideStatus.running;
    
    // Connect to the device adapter if not already connected
    if (_activeAdapter != null && !_activeAdapter!.isConnected) {
      await _activeAdapter!.connect(null);
    }
    
    // Start simulation timer
    _simulationTimer = Timer.periodic(
      AppConstants.simulationTickInterval,
      (_) => _updateSimulation(),
    );

    notifyListeners();
  }

  /// Pause the ride
  void pauseRide() {
    if (_status != RideStatus.running) return;

    _status = RideStatus.paused;
    _pauseStartTime = DateTime.now();
    _simulationTimer?.cancel();
    
    notifyListeners();
  }

  /// Resume the ride
  void resumeRide() {
    if (_status != RideStatus.paused) return;

    if (_pauseStartTime != null) {
      _pausedTime += DateTime.now().difference(_pauseStartTime!);
    }

    startRide();
  }

  /// Cancel the ride
  Future<RideSummary> cancelRide() async {
    // If ride hasn't started, just reset without changing status to cancelled
    if (_startTime == null) {
      _resetMetrics();
      notifyListeners();
      throw Exception('Cannot cancel a ride that has not started');
    }
    
    _status = RideStatus.cancelled;
    _endTime = DateTime.now();
    _simulationTimer?.cancel();
    
    // Clean up device
    if (_activeDevice != null) {
      _activeDevice!.dispose();
    }
    if (_activeAdapter != null) {
      await _activeAdapter!.disconnect();
      _activeAdapter = null;
    }

    final summary = await _generateSummary(completed: false, cancellationReason: 'user_cancelled');
    
    // Auto-save cancelled ride to history
    _autoSaveRide(summary);
    
    _resetMetrics();
    
    notifyListeners();
    return summary;
  }

  /// Complete the ride
  Future<RideSummary> completeRide() async {
    // If already have a summary (already completed), return it
    if (_lastSummary != null) {
      return _lastSummary!;
    }
    
    // If ride hasn't started, return early without throwing
    if (_startTime == null || _route == null) {
      // Don't throw, just return to avoid infinite loop in UI
      return RideSummary(
        totalDuration: Duration.zero,
        movingTime: Duration.zero,
        pausedTime: Duration.zero,
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        totalDistance: 0,
        completedDistance: 0,
        completionPercentage: 0,
        averageSpeed: 0,
        averageMovingSpeed: 0,
        maxSpeed: 0,
        minSpeed: 0,
        totalElevationGain: 0,
        totalElevationLoss: 0,
        maxGrade: 0,
        minGrade: 0,
        currentElevation: 0,
        caloriesBurned: 0,
        averagePower: 0,
        routeId: '',
        routeName: 'Unknown',
        completed: false,
        cancellationReason: 'ride_not_started',
        startInput: null,
        endInput: null,
        waypointInputs: null,
      );
    }
    
    // Cancel timer first to prevent race conditions
    _simulationTimer?.cancel();
    _simulationTimer = null;
    
    _status = RideStatus.completed;
    _endTime = DateTime.now();

    RideSummary summary;
    try {
      summary = await _generateSummary(completed: true);
    } catch (e) {
      // Return a basic summary if generation fails
      summary = RideSummary(
        totalDuration: _totalDuration,
        movingTime: _movingTime,
        pausedTime: _pausedTime,
        startTime: _startTime ?? DateTime.now(),
        endTime: _endTime ?? DateTime.now(),
        totalDistance: _route?.geometry.totalDistance ?? 0,
        completedDistance: _completedDistance,
        completionPercentage: 0,
        averageSpeed: 0,
        averageMovingSpeed: 0,
        maxSpeed: _maxSpeed,
        minSpeed: _minSpeed == double.infinity ? 0 : _minSpeed,
        totalElevationGain: 0,
        totalElevationLoss: 0,
        maxGrade: _maxGrade * 100,
        minGrade: _minGrade * 100,
        currentElevation: _currentElevation,
        caloriesBurned: 0,
        averagePower: 0,
        routeId: _route?.id ?? '',
        routeName: _route?.displayName ?? 'Unknown',
        completed: true,
        cancellationReason: null,
        startInput: _route?.startInput,
        endInput: _route?.endInput,
        waypointInputs: _route?.waypointInputs,
      );
    }
    
    _lastSummary = summary;
    // Don't reset metrics here - let the next ride initialization do it
    // This keeps startTime available for UI navigation check
    
    // Auto-save completed ride to history
    await _autoSaveRide(summary);
    
    notifyListeners();
    return summary;
  }

  /// Auto-save ride to history
  Future<void> _autoSaveRide(RideSummary summary) async {
    try {
      final storage = RouteStorageService();
      await storage.init(); // Ensure storage is initialized
      await storage.saveRideHistory(summary);
      print('✅ Ride saved to history: ${summary.routeName}');
    } catch (e) {
      print('❌ Failed to save ride: $e');
      // Silently fail - user can manually save from summary screen
    }
  }

  /// Update simulation state
  void _updateSimulation() {
    if (_route == null || _status != RideStatus.running || _startTime == null) return;

    final deltaTime = AppConstants.simulationTickInterval.inMilliseconds / 1000.0;

    // Get current grade
    if (_currentSegmentIndex < _route!.elevationProfile.grades.length) {
      _currentGrade = _route!.elevationProfile.grades[_currentSegmentIndex];
    }

    // If we have an active device, use it for metrics
    if (_activeDevice != null) {
      // Simulate device with current conditions
      final deviceData = _activeDevice!.simulate(
        deltaTime: deltaTime,
        routeGrade: _currentGrade,
        intensityMultiplier: _workoutIntensity,
      );

      // For real devices (FTMS), use device speed directly, don't calculate
      // For virtual devices, speed should always be available from simulate()
      _currentSpeed = deviceData.speed ?? 0.0;

      // Update device-specific metrics
      if (deviceData.cadenceOrPace != null) {
        _currentCadence = deviceData.cadenceOrPace!;
        _cadenceSamples.add(_currentCadence);
      }
      if (deviceData.heartRate != null) {
        _currentHeartRate = deviceData.heartRate!.toDouble();
        _heartRateSamples.add(_currentHeartRate);
      }

      // Send control commands to device based on route grade and intensity
      final isBike = _activeDevice!.deviceType == DeviceType.indoorBike;
      
      if (isBike) {
        // Map grade percentage to resistance and apply intensity multiplier
        // Grade is stored as decimal (0.05 = 5%), convert to percentage first
        final gradePercent = _currentGrade * 100;
        // Get device resistance range
        final minRes = 1.0;
        final maxRes = 32.0;
        // Map -5% to 15% grade range to device resistance range
        // 0% = 25% of range, scaling factor based on range
        final rangeSize = maxRes - minRes;
        final baseResistance = (gradePercent * (rangeSize / 20.0) + minRes + (rangeSize * 0.25)).clamp(minRes, maxRes);
        final adjustedResistance = (baseResistance * _workoutIntensity).clamp(minRes, maxRes).round();
        _activeDevice!.sendControlCommand(SetResistance(adjustedResistance));
      } else {
        // Map grade to incline percentage and apply intensity multiplier
        final baseIncline = (_currentGrade * 100).clamp(-3.0, 15.0);
        final adjustedIncline = (baseIncline * _workoutIntensity).clamp(-3.0, 15.0);
        _activeDevice!.sendControlCommand(SetIncline(adjustedIncline));
      }

      // Use device power if available
      if (deviceData.power != null) {
        _powerSamples.add(PowerSample(
          power: deviceData.power!,
          timestamp: DateTime.now(),
        ));
      }
    } else {
      // No device - use calculated speed
      _currentSpeed = RideCalculator.calculateAdjustedSpeed(
        baseSpeed: AppConstants.baseSpeedKmh,
        grade: _currentGrade,
        speedMultiplier: AppConstants.speedMultiplier,
        gradeAdjustmentFactor: AppConstants.gradeAdjustmentFactor,
      );

      // Calculate power for non-device rides
      final power = RideCalculator.estimatePower(
        speedKmh: _currentSpeed,
        grade: _currentGrade,
      );
      _powerSamples.add(PowerSample(power: power, timestamp: DateTime.now()));
    }

    // Track speed statistics
    if (_currentSpeed > _maxSpeed) _maxSpeed = _currentSpeed;
    if (_currentSpeed < _minSpeed && _currentSpeed > AppConstants.minimumMovingSpeed) {
      _minSpeed = _currentSpeed;
    }
    _speedSamples.add(_currentSpeed);

    // Track grade statistics
    if (_currentGrade > _maxGrade) _maxGrade = _currentGrade;
    if (_currentGrade < _minGrade) _minGrade = _currentGrade;

    // Calculate distance moved in this tick
    final speedMs = _currentSpeed / 3.6;
    final distanceMoved = speedMs * deltaTime;

    // Update position
    _updatePosition(distanceMoved);

    // Update time tracking (safe access after guard clause check)
    final startTime = _startTime;
    if (startTime != null) {
      _totalDuration = DateTime.now().difference(startTime);
      if (_currentSpeed > AppConstants.minimumMovingSpeed) {
        _movingTime += AppConstants.simulationTickInterval;
      }
    }

    notifyListeners();
  }

  /// Update position along route
  void _updatePosition(double distanceMoved) {
    if (_route == null) return;

    final waypoints = _route!.coordinates.waypoints;
    final segmentDistances = _route!.geometry.segmentDistances;

    if (_currentSegmentIndex >= segmentDistances.length) {
      // Reached the end
      completeRide();
      return;
    }

    final currentSegmentDistance = segmentDistances[_currentSegmentIndex];
    final distanceInSegment = _progressInSegment * currentSegmentDistance;
    final newDistanceInSegment = distanceInSegment + distanceMoved;

    _completedDistance += distanceMoved;

    if (newDistanceInSegment >= currentSegmentDistance) {
      // Move to next segment
      final overflow = newDistanceInSegment - currentSegmentDistance;
      _currentSegmentIndex++;
      
      if (_currentSegmentIndex >= waypoints.length - 1) {
        // Reached destination - only complete if not already completed
        if (_status == RideStatus.running) {
          _currentPosition = _route!.coordinates.end;
          _currentElevation = _route!.elevationProfile.elevations.last;
          completeRide();
        }
        return;
      }

      _progressInSegment = overflow / segmentDistances[_currentSegmentIndex];
    } else {
      _progressInSegment = newDistanceInSegment / currentSegmentDistance;
    }

    // Interpolate position
    final start = waypoints[_currentSegmentIndex].toLatLng();
    final end = waypoints[_currentSegmentIndex + 1].toLatLng();

    final lat = start.latitude + (end.latitude - start.latitude) * _progressInSegment;
    final lng = start.longitude + (end.longitude - start.longitude) * _progressInSegment;
    _currentPosition = LatLng(lat, lng);

    // Calculate bearing for this segment
    final distance = const Distance();
    _currentBearing = distance.bearing(start, end);

    // Interpolate elevation
    final startElev = _route!.elevationProfile.elevations[_currentSegmentIndex];
    final endElev = _route!.elevationProfile.elevations[_currentSegmentIndex + 1];
    final newElevation = startElev + (endElev - startElev) * _progressInSegment;
    
    // Track elevation gain for calories
    if (newElevation > _currentElevation) {
      _totalElevationGained += (newElevation - _currentElevation);
    }
    _currentElevation = newElevation;
    
    // Update real-time calories using cached body weight
    final avgSpeed = _completedDistance > 0 && _movingTime.inSeconds > 0
        ? (_completedDistance / _movingTime.inSeconds) * 3.6
        : 0.0;
    double met;
    if (avgSpeed < 16) {
      met = 8.0;
    } else if (avgSpeed < 25) {
      met = 10.0;
    } else {
      met = 12.0;
    }
    met += (_totalElevationGained / 100) * 0.5;
    final hours = _movingTime.inSeconds / 3600.0;
    _currentCalories = met * _cachedBodyWeight * hours;
  }

  /// Generate ride summary
  Future<RideSummary> _generateSummary({
    required bool completed,
    String? cancellationReason,
  }) async {
    if (_route == null || _startTime == null) {
      throw Exception('Cannot generate summary without a route and start time');
    }

    // Save values before reset
    final startTime = _startTime!;
    final endTime = _endTime ?? DateTime.now();

    final avgSpeed = _speedSamples.isNotEmpty
        ? _speedSamples.reduce((a, b) => a + b) / _speedSamples.length
        : 0.0;

    final avgMovingSpeed = RideCalculator.calculateAverageSpeed(
      _completedDistance,
      _movingTime,
    );

    final avgPower = RideCalculator.calculateAveragePower(_powerSamples);

    // Calculate elevation metrics for completed portion
    final elevationChange = _currentSegmentIndex > 0
        ? RideCalculator.calculateElevationChange(
            _route!.elevationProfile.elevations.sublist(0, _currentSegmentIndex + 1))
        : ElevationChange(gain: 0, loss: 0);

    // Get user's body weight from profile
    final profile = await ProfileService().getProfile();
    final bodyWeight = profile?.bodyWeight ?? 70.0;

    final calories = RideCalculator.estimateCalories(
      distanceMeters: _completedDistance,
      elevationGainMeters: elevationChange.gain,
      duration: _movingTime,
      riderWeightKg: bodyWeight,
    );

    final completionPercentage = _route!.geometry.totalDistance > 0
        ? (_completedDistance / _route!.geometry.totalDistance * 100).clamp(0, 100).toDouble()
        : 0.0;

    return RideSummary(
      totalDuration: _totalDuration,
      movingTime: _movingTime,
      pausedTime: _pausedTime,
      startTime: startTime,
      endTime: endTime,
      totalDistance: _route!.geometry.totalDistance,
      completedDistance: _completedDistance,
      completionPercentage: completionPercentage,
      averageSpeed: avgSpeed,
      averageMovingSpeed: avgMovingSpeed,
      maxSpeed: _maxSpeed,
      minSpeed: _minSpeed == double.infinity ? 0 : _minSpeed,
      totalElevationGain: elevationChange.gain,
      totalElevationLoss: elevationChange.loss,
      maxGrade: _maxGrade * 100,
      minGrade: _minGrade * 100,
      currentElevation: _currentElevation,
      caloriesBurned: calories,
      averagePower: avgPower,
      routeId: _route!.id,
      routeName: _route!.displayName,
      completed: completed,
      cancellationReason: cancellationReason,
      routeThumbnail: _routeThumbnail,
      startInput: _route!.startInput,
      endInput: _route!.endInput,
      waypointInputs: _route!.waypointInputs,
    );
  }

  /// Reset all metrics
  void _resetMetrics() {
    _currentSegmentIndex = 0;
    _progressInSegment = 0.0;
    _currentPosition = null;
    _startTime = null;
    _endTime = null;
    _totalDuration = Duration.zero;
    _movingTime = Duration.zero;
    _pausedTime = Duration.zero;
    _pauseStartTime = null;
    _completedDistance = 0.0;
    _currentSpeed = 0.0;
    _maxSpeed = 0.0;
    _minSpeed = double.infinity;
    _speedSamples = [];
    _lastSummary = null;
    _currentElevation = 0.0;
    _currentGrade = 0.0;
    _maxGrade = double.negativeInfinity;
    _minGrade = double.infinity;
    _powerSamples = [];
    _currentCadence = 0.0;
    _currentHeartRate = 0.0;
    _cadenceSamples = [];
    _heartRateSamples = [];
    _workoutIntensity = 1.0;
    _activeDevice = null;
    _currentCalories = 0.0;
    _totalElevationGained = 0.0;
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    _deviceConnectionSubscription?.cancel();
    super.dispose();
  }

  /// Generate a simple thumbnail image from route data
  /// Creates a basic colored image representing the route
  Uint8List _generateSimpleThumbnail(SavedRoute route) {
    try {
      // For now, return a simple PNG image (1x1 pixel gradient)
      // This avoids the complexity of map rendering
      // Real implementation would capture the map widget
      // Return a simple placeholder - will show as checkmark in UI
      // but this is better than nothing
      
      // Create a simple 200x200 gradient PNG
      final data = ByteData(12);
      data.setUint8(0, 137); // PNG signature
      data.setUint8(1, 80);
      data.setUint8(2, 78);
      data.setUint8(3, 71);
      data.setUint8(4, 13);
      data.setUint8(5, 10);
      data.setUint8(6, 26);
      data.setUint8(7, 10);
      data.setUint8(8, 0);
      data.setUint8(9, 0);
      data.setUint8(10, 0);
      data.setUint8(11, 13);
      
      return data.buffer.asUint8List();
    } catch (e) {
      // Return empty if generation fails
      return Uint8List(0);
    }
  }
}

/// Wrapper that adapts DeviceAdapter to VirtualFitnessDevice interface
class _DeviceAdapterWrapper extends VirtualFitnessDevice {
  final DeviceAdapter _adapter;
  final SavedDevice _device;
  DeviceMetrics? _lastMetrics;
  StreamSubscription? _metricsSubscription;
  
  _DeviceAdapterWrapper(this._adapter, this._device) {
    // Subscribe to metrics stream to cache latest metrics
    _metricsSubscription = _adapter.metricsStream.listen((metrics) {
      _lastMetrics = metrics;
    });
  }
  
  @override
  DeviceType get deviceType {
    if (_device.adapterType == 'virtualBike') {
      return DeviceType.indoorBike;
    } else if (_device.adapterType == 'virtualTreadmill') {
      return DeviceType.treadmill;
    } else {
      return DeviceType.indoorBike; // Default fallback
    }
  }
  
  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {
    // For now, this is handled directly by sendControlCommand
    // This method is here to satisfy the interface
  }
  
  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    // Return the latest metrics from the adapter
    if (_lastMetrics != null) {
      return DeviceDataSnapshot(
        speed: _lastMetrics!.speed,
        cadenceOrPace: _lastMetrics!.cadence,
        heartRate: _lastMetrics!.heartRate,
        power: _lastMetrics!.power?.toDouble(),
      );
    }
    
    // Fallback if no metrics yet
    return DeviceDataSnapshot(
      speed: 0.0,
      cadenceOrPace: null,
      heartRate: null,
      power: null,
    );
  }
  
  @override
  Future<bool> sendControlCommand(ControlCommand command) async {
    try {
      if (command is SetResistance) {
        await _adapter.setResistance(command.level);
        return true;
      } else if (command is SetIncline) {
        await _adapter.setIncline(command.percentage);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
  
  @override
  Uint8List getFTMSDataPacket() {
    // Not used by virtual devices
    return Uint8List(0);
  }
  
  @override
  void dispose() {
    _metricsSubscription?.cancel();
    _adapter.dispose();
  }
}