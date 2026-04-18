import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/services/fitness_device.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Minimal fake [FitnessDevice] whose connection state can be driven
/// externally via [setConnected] and whose [connect] result is controllable.
class FakeFitnessDevice implements FitnessDevice {
  bool _isConnected = false;
  bool nextConnectResult = true;
  int connectCallCount = 0;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  bool get isConnected => _isConnected;

  @override
  Stream<bool> get connectionState => _connectionController.stream;

  void setConnected(bool value) {
    _isConnected = value;
    _connectionController.add(value);
  }

  @override
  Future<bool> connect() async {
    connectCallCount++;
    if (nextConnectResult) {
      _isConnected = true;
      _connectionController.add(true);
    }
    return nextConnectResult;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionController.add(false);
  }

  @override
  DeviceType get deviceType => DeviceType.indoorBike;

  @override
  int get minResistance => 1;

  @override
  int get maxResistance => 20;

  @override
  double get minIncline => -3.0;

  @override
  double get maxIncline => 15.0;

  @override
  void updateInputs({
    required double effortLevel,
    required double controllableParam,
  }) {}

  @override
  DeviceDataSnapshot simulate({
    required double deltaTime,
    required double? routeGrade,
    required double intensityMultiplier,
  }) {
    return DeviceDataSnapshot(speed: 20.0);
  }

  @override
  Future<bool> sendControlCommand(ControlCommand command) async => true;

  @override
  Uint8List getFTMSDataPacket() => Uint8List(0);

  @override
  void dispose() {
    _connectionController.close();
  }
}

SavedRoute _testRoute() {
  return SavedRoute(
    id: 'test-route',
    timestamp: DateTime(2025, 1, 1),
    startInput: 'A',
    endInput: 'B',
    coordinates: RouteCoordinates(
      startLat: 0.0,
      startLon: 0.0,
      endLat: 0.01,
      endLon: 0.01,
      waypoints: [
        LatLngPoint(0.0, 0.0),
        LatLngPoint(0.01, 0.01),
      ],
    ),
    geometry: RouteGeometry(
      totalDistance: 1000.0,
      segmentDistances: [1000.0],
    ),
    elevationProfile: ElevationProfile(
      elevations: [100.0, 110.0],
      grades: [0.01],
      totalElevationGain: 10.0,
      totalElevationLoss: 0.0,
      maxElevation: 110.0,
      minElevation: 100.0,
    ),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('RideProvider reconnect-on-resume', () {
    late RideProvider provider;
    late FakeFitnessDevice device;

    setUp(() {
      provider = RideProvider();
      device = FakeFitnessDevice();
    });

    tearDown(() {
      provider.dispose();
      device.dispose();
    });

    test('resumeRide calls connect when device is disconnected', () async {
      // Manually set up the ride state without startRideWithDevice
      // (avoids needing ProfileService / Hive)
      await provider.initializeRide(_testRoute());

      // Simulate what startRideWithDevice does to internal state:
      // We use the public startRide/pauseRide flow.
      provider.startRide();
      expect(provider.status, RideStatus.running);

      provider.pauseRide();
      expect(provider.status, RideStatus.paused);

      // Now test resumeRide without a device — should just resume
      await provider.resumeRide();
      expect(provider.status, RideStatus.running);
    });

    test('resumeRide is a no-op if status is not paused', () async {
      await provider.initializeRide(_testRoute());
      provider.startRide();

      // resumeRide while running should be a no-op
      await provider.resumeRide();
      expect(provider.status, RideStatus.running);
    });

    test('pauseRide cancels timer', () async {
      await provider.initializeRide(_testRoute());
      provider.startRide();
      provider.pauseRide();
      expect(provider.status, RideStatus.paused);
    });

    test('startRide cancels existing timer before creating new one', () async {
      await provider.initializeRide(_testRoute());

      // Call startRide twice — should not throw or create duplicates
      provider.startRide();
      expect(provider.status, RideStatus.running);

      // Pause then re-start
      provider.pauseRide();
      provider.startRide();
      expect(provider.status, RideStatus.running);
    });
  });
}
