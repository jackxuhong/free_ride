import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/models/ride_summary.dart';
import 'package:free_ride/models/duration_adapter.dart';
import 'package:free_ride/utils/constants.dart';

class RouteStorageService {
  static final RouteStorageService _instance = RouteStorageService._internal();
  factory RouteStorageService() => _instance;
  RouteStorageService._internal();

  late Box<SavedRoute> _routesBox;
  late Box<RideSummary> _historyBox;
  late Box<dynamic> _settingsBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // Note: Hive.initFlutter() is now called in main.dart before any service initialization
    
    // Register adapters
    Hive.registerAdapter(DurationAdapter());
    Hive.registerAdapter(SavedRouteAdapter());
    Hive.registerAdapter(RouteCoordinatesAdapter());
    Hive.registerAdapter(LatLngPointAdapter());
    Hive.registerAdapter(RouteGeometryAdapter());
    Hive.registerAdapter(ElevationProfileAdapter());
    Hive.registerAdapter(RideSummaryAdapter());

    // Open boxes
    _routesBox = await Hive.openBox<SavedRoute>(AppConstants.routesBoxName);
    _historyBox = await Hive.openBox<RideSummary>(AppConstants.historyBoxName);
    _settingsBox = await Hive.openBox(AppConstants.settingsBoxName);

    _initialized = true;
  }

  // Save a new route
  Future<void> saveRoute(SavedRoute route) async {
    await _routesBox.put(route.id, route);
    await _setLastRouteId(route.id);
  }

  // Update route custom name
  Future<void> updateRouteName(String routeId, String? customName) async {
    final route = _routesBox.get(routeId);
    if (route != null) {
      final updatedRoute = SavedRoute(
        id: route.id,
        timestamp: route.timestamp,
        startInput: route.startInput,
        endInput: route.endInput,
        coordinates: route.coordinates,
        geometry: route.geometry,
        elevationProfile: route.elevationProfile,
        customName: customName,
        waypointInputs: route.waypointInputs,
      );
      await _routesBox.put(routeId, updatedRoute);
    }
  }

  // Get last used route (for quick repeat)
  Future<SavedRoute?> getLastRoute() async {
    final lastId = _settingsBox.get(AppConstants.lastRouteKey) as String?;
    if (lastId == null) return null;
    return _routesBox.get(lastId);
  }

  // Get specific route by ID
  SavedRoute? getRouteById(String id) {
    return _routesBox.get(id);
  }

  // Get all saved routes
  List<SavedRoute> getAllRoutes() {
    final routes = _routesBox.values.toList();
    routes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return routes;
  }

  // Delete a route
  Future<void> deleteRoute(String id) async {
    await _routesBox.delete(id);
  }

  // Save ride summary to history
  Future<void> saveRideHistory(RideSummary summary) async {
    // Create a detached copy to avoid HiveObject duplicate key error
    final summaryToSave = summary.copyForSave();
    await _historyBox.add(summaryToSave);

    // Cleanup old history if exceeded max size
    if (_historyBox.length > AppConstants.maxHistorySize) {
      final keys = _historyBox.keys.toList();
      keys.sort(); // Sort keys to get oldest first
      final oldestKey = keys.first;
      await _historyBox.delete(oldestKey);
    }
  }

  // Get ride history
  List<RideSummary> getRideHistory({int limit = 20}) {
    final history = _historyBox.values.toList();
    history.sort((a, b) => b.startTime.compareTo(a.startTime));
    return history.take(limit).toList();
  }

  // Get ride history for a specific route
  List<RideSummary> getRideHistoryForRoute(String routeId, {int limit = 10}) {
    final history = _historyBox.values
        .where((summary) => summary.routeId == routeId)
        .toList();
    history.sort((a, b) => b.startTime.compareTo(a.startTime));
    return history.take(limit).toList();
  }

  // Delete ride from history
  Future<void> deleteRideHistory(RideSummary summary) async {
    final key = summary.key;
    if (key != null) {
      await _historyBox.delete(key);
    }
  }

  // Update ride name
  Future<void> updateRideName(RideSummary summary, String newName) async {
    final key = summary.key;
    if (key != null) {
      summary.routeName = newName;
      await summary.save();
    }
  }

  // Clear all history
  Future<void> clearAllHistory() async {
    await _historyBox.clear();
  }

  // Clear all routes
  Future<void> clearAllRoutes() async {
    await _routesBox.clear();
    await _settingsBox.delete(AppConstants.lastRouteKey);
  }

  // Private helper to set last route ID
  Future<void> _setLastRouteId(String id) async {
    await _settingsBox.put(AppConstants.lastRouteKey, id);
  }

  // Get storage statistics
  Map<String, int> getStorageStats() {
    return {
      'totalRoutes': _routesBox.length,
      'totalRides': _historyBox.length,
    };
  }
}
