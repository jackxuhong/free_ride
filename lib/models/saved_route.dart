import 'package:hive/hive.dart';
import 'package:latlong2/latlong.dart';

part 'saved_route.g.dart';

@HiveType(typeId: 0)
class SavedRoute extends HiveObject {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final DateTime timestamp;
  
  @HiveField(2)
  final String startInput; // Original user input (address or coordinates)
  
  @HiveField(3)
  final String endInput; // Original user input (address or coordinates)
  
  @HiveField(4)
  final RouteCoordinates coordinates;
  
  @HiveField(5)
  final RouteGeometry geometry;
  
  @HiveField(6)
  final ElevationProfile elevationProfile;
  
  @HiveField(7)
  final String? customName;
  
  @HiveField(8)
  final List<String>? waypointInputs; // Original waypoint inputs

  SavedRoute({
    required this.id,
    required this.timestamp,
    required this.startInput,
    required this.endInput,
    required this.coordinates,
    required this.geometry,
    required this.elevationProfile,
    this.customName,
    this.waypointInputs,
  });
  
  String get displayName => customName ?? '$startInput → $endInput';
  
  String get fullRouteDisplay {
    final parts = [startInput];
    if (waypointInputs != null && waypointInputs!.isNotEmpty) {
      parts.addAll(waypointInputs!);
    }
    parts.add(endInput);
    return parts.join(' → ');
  }
}

@HiveType(typeId: 1)
class RouteCoordinates {
  @HiveField(0)
  final double startLat;
  
  @HiveField(1)
  final double startLon;
  
  @HiveField(2)
  final double endLat;
  
  @HiveField(3)
  final double endLon;
  
  @HiveField(4)
  final List<LatLngPoint> waypoints;

  RouteCoordinates({
    required this.startLat,
    required this.startLon,
    required this.endLat,
    required this.endLon,
    required this.waypoints,
  });
  
  LatLng get start => LatLng(startLat, startLon);
  LatLng get end => LatLng(endLat, endLon);
}

@HiveType(typeId: 2)
class LatLngPoint {
  @HiveField(0)
  final double latitude;
  
  @HiveField(1)
  final double longitude;

  LatLngPoint(this.latitude, this.longitude);
  
  LatLng toLatLng() => LatLng(latitude, longitude);
  
  factory LatLngPoint.fromLatLng(LatLng latLng) {
    return LatLngPoint(latLng.latitude, latLng.longitude);
  }
}

@HiveType(typeId: 3)
class RouteGeometry {
  @HiveField(0)
  final double totalDistance; // meters
  
  @HiveField(1)
  final List<double> segmentDistances; // distance between each waypoint

  RouteGeometry({
    required this.totalDistance,
    required this.segmentDistances,
  });
  
  double get totalDistanceKm => totalDistance / 1000.0;
}

@HiveType(typeId: 4)
class ElevationProfile {
  @HiveField(0)
  final List<double> elevations; // meters, one per waypoint
  
  @HiveField(1)
  final List<double> grades; // percentage grade between points
  
  @HiveField(2)
  final double totalElevationGain; // meters
  
  @HiveField(3)
  final double totalElevationLoss; // meters
  
  @HiveField(4)
  final double maxElevation; // meters
  
  @HiveField(5)
  final double minElevation; // meters

  ElevationProfile({
    required this.elevations,
    required this.grades,
    required this.totalElevationGain,
    required this.totalElevationLoss,
    required this.maxElevation,
    required this.minElevation,
  });
  
  String get difficulty {
    if (elevations.isEmpty || totalDistance == 0) return 'Unknown';
    final gainPerKm = totalElevationGain / (totalDistance / 1000.0);
    if (gainPerKm < 10.0) return 'Easy';
    if (gainPerKm < 30.0) return 'Moderate';
    return 'Hard';
  }
  
  double get totalDistance {
    if (grades.isEmpty || elevations.length < 2) return 0.0;
    // Approximate total distance from elevation differences and grades.
    // grade = rise / run  =>  run = rise / grade (when grade != 0).
    // For zero-grade segments we fall back to a rough per-point spacing.
    double total = 0.0;
    for (int i = 0; i < grades.length; i++) {
      final rise = (elevations[i + 1] - elevations[i]).abs();
      if (grades[i].abs() > 0.001) {
        total += rise / grades[i].abs();
      } else {
        // Flat segment — estimate from neighbouring segments
        total += 10.0; // 10 m default spacing
      }
    }
    return total;
  }
}
