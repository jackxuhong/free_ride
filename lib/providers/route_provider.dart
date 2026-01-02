import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/services/geocoding_service.dart';
import 'package:free_ride/services/openroute_service.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/services/ride_calculator.dart';

class RouteProvider with ChangeNotifier {
  final _geocodingService = GeocodingService();
  final _openRouteService = OpenRouteService();
  final _storageService = RouteStorageService();

  SavedRoute? _currentRoute;
  bool _isLoading = false;
  String? _error;

  SavedRoute? get currentRoute => _currentRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Set the current route (useful for repeating rides)
  void setCurrentRoute(SavedRoute route) {
    _currentRoute = route;
    notifyListeners();
  }

  /// Fetch route from start to end location
  Future<void> fetchRoute(String startInput, String endInput) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Geocode start and end locations
      final startLatLng = await _geocodingService.geocode(startInput);
      final endLatLng = await _geocodingService.geocode(endInput);

      // Get readable addresses
      final startAddress = await _geocodingService.reverseGeocode(startLatLng);
      final endAddress = await _geocodingService.reverseGeocode(endLatLng);

      // Fetch route from OpenRouteService
      final routeResponse = await _openRouteService.getRoute(
        startLatLng,
        endLatLng,
      );

      // Parse route data
      final routeData = _openRouteService.parseRouteData(routeResponse);

      // Calculate segment distances
      final segmentDistances = _openRouteService.calculateSegmentDistances(
        routeData.coordinates,
      );

      // Calculate grades
      final grades = RideCalculator.calculateGrades(
        routeData.elevations,
        segmentDistances,
      );

      // Calculate elevation statistics
      final elevationChange = RideCalculator.calculateElevationChange(
        routeData.elevations,
      );

      final maxElevation = routeData.elevations.reduce((a, b) => a > b ? a : b);
      final minElevation = routeData.elevations.reduce((a, b) => a < b ? a : b);

      // Create route model
      final route = SavedRoute(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        startAddress: startAddress,
        endAddress: endAddress,
        coordinates: RouteCoordinates(
          startLat: startLatLng.latitude,
          startLon: startLatLng.longitude,
          endLat: endLatLng.latitude,
          endLon: endLatLng.longitude,
          waypoints: routeData.coordinates
              .map((coord) => LatLngPoint.fromLatLng(coord))
              .toList(),
        ),
        geometry: RouteGeometry(
          totalDistance: routeData.totalDistance,
          segmentDistances: segmentDistances,
        ),
        elevationProfile: ElevationProfile(
          elevations: routeData.elevations,
          grades: grades,
          totalElevationGain: elevationChange.gain,
          totalElevationLoss: elevationChange.loss,
          maxElevation: maxElevation,
          minElevation: minElevation,
        ),
      );

      // Save route
      await _storageService.saveRoute(route);

      _currentRoute = route;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Load an existing route
  void loadRoute(SavedRoute route) {
    _currentRoute = route;
    _error = null;
    notifyListeners();
  }

  /// Clear current route
  void clearRoute() {
    _currentRoute = null;
    _error = null;
    notifyListeners();
  }

  /// Update route custom name
  Future<void> updateRouteName(String? customName) async {
    if (_currentRoute == null) return;

    await _storageService.updateRouteName(_currentRoute!.id, customName);
    
    // Reload route to get updated name
    final updatedRoute = _storageService.getRouteById(_currentRoute!.id);
    if (updatedRoute != null) {
      _currentRoute = updatedRoute;
      notifyListeners();
    }
  }
}
