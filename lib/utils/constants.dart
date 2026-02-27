/// Application-wide constants and configuration values
class AppConstants {
  // Simulation Parameters
  static const double baseSpeedKmh = 20.0;
  static const double speedMultiplier = 10.0;
  static const double gradeAdjustmentFactor = 0.1;
  
  // Nominatim API Configuration
  static const String nominatimUserAgent = 'FreeRide/1.0 (contact@freeride.app)';
  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const Duration nominatimRateLimit = Duration(seconds: 1);
  
  // Generate user agent with email from profile
  static String getUserAgent(String email) {
    return 'FreeRide/1.0 ($email)';
  }
  
  // Storage Configuration
  static const int maxHistorySize = 50;
  static const String routesBoxName = 'saved_routes';
  static const String historyBoxName = 'ride_history';
  static const String settingsBoxName = 'settings';
  static const String lastRouteKey = 'last_route_id';
  
  // Map Configuration
  static const String osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const double defaultMapZoom = 13.0;
  static const int maxMapZoom = 18;
  static const int minMapZoom = 3;
  
  // Ride Simulation
  static const Duration simulationTickInterval = Duration(milliseconds: 100);
  static const double minimumMovingSpeed = 0.1; // km/h
  
  // OpenRouteService API
  static const String openRouteServiceBaseUrl = 'https://api.openrouteservice.org';
  static const String directionsEndpoint = '/v2/directions/cycling-regular';
  static const String elevationEndpoint = '/elevation/line';
  
  // UI Constants
  static const double defaultPadding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;

  // Default values
  static const double defaultBodyWeightKg = 70.0;
  static const String mapUserAgentPackageName = 'com.example.free_ride';

  // Virtual device limits
  static const double maxVirtualBikeSpeedKmh = 50.0;
  static const double maxVirtualTreadmillSpeedKmh = 20.0;
  
  // Route Difficulty Thresholds (based on elevation gain per km)
  static const double easyRouteThreshold = 10.0; // meters per km
  static const double moderateRouteThreshold = 30.0; // meters per km
  // Above moderate is considered hard
  
  // Speed calculation helper
  static double get effectiveSpeedKmh => baseSpeedKmh * speedMultiplier;
  static double get effectiveSpeedMs => effectiveSpeedKmh / 3.6;
  
  // Prevent instantiation
  AppConstants._();

  /// Formats a [Duration] as a human-readable string.
  ///
  /// Examples: `'1h 23m'`, `'5m 12s'`, `'30s'`.
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
