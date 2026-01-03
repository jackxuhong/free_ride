import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:free_ride/utils/constants.dart';

class OpenRouteService {
  static final OpenRouteService _instance = OpenRouteService._internal();
  factory OpenRouteService() => _instance;
  OpenRouteService._internal();

  String get _apiKey => dotenv.env['OPENROUTE_SERVICE_API_KEY'] ?? '';

  /// Get cycling route with optional waypoints between start and end
  /// waypoints: list of intermediate stops between start and end
  Future<Map<String, dynamic>> getRoute(
    LatLng start,
    LatLng end, {
    List<LatLng>? waypoints,
  }) async {
    final url = Uri.parse(
      '${AppConstants.openRouteServiceBaseUrl}${AppConstants.directionsEndpoint}',
    );

    // Build coordinates array: start, waypoints (if any), end
    final coordinates = <List<double>>[
      [start.longitude, start.latitude],
      if (waypoints != null)
        ...waypoints.map((w) => [w.longitude, w.latitude]),
      [end.longitude, end.latitude],
    ];

    final body = json.encode({
      'coordinates': coordinates,
      'elevation': true,
      'instructions': false,
    });

    final response = await http.post(
      url,
      headers: {
        'Authorization': _apiKey,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      print('Route API Error: ${response.statusCode}');
      print('Response body: ${response.body}');
      throw Exception(
        'Failed to get route: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Get elevation profile for a route
  Future<Map<String, dynamic>> getElevationProfile(
    List<LatLng> coordinates,
  ) async {
    final url = Uri.parse(
      '${AppConstants.openRouteServiceBaseUrl}${AppConstants.elevationEndpoint}',
    );

    final body = json.encode({
      'format_in': 'geojson',
      'geometry': {
        'coordinates': coordinates
            .map((coord) => [coord.longitude, coord.latitude])
            .toList(),
        'type': 'LineString',
      },
    });

    final response = await http.post(
      url,
      headers: {
        'Authorization': _apiKey,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(
        'Failed to get elevation: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Parse route data from OpenRouteService response
  RouteData parseRouteData(Map<String, dynamic> routeResponse) {
    final routes = routeResponse['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw Exception('No route found in response');
    }

    final route = routes[0] as Map<String, dynamic>;
    final geometryEncoded = route['geometry'] as String?;
    final summary = route['summary'] as Map<String, dynamic>?;

    if (geometryEncoded == null || summary == null) {
      throw Exception('Invalid route response structure');
    }

    // Decode the polyline geometry (includes elevation as 3rd dimension)
    final decodedPoints = _decodePolyline(geometryEncoded, include3D: true);
    
    if (decodedPoints.isEmpty) {
      throw Exception('Failed to decode route geometry');
    }

    // Extract coordinates and elevations
    final coords = decodedPoints
        .map((point) => LatLng(point[0], point[1]))
        .toList();

    final elevations = decodedPoints
        .map((point) => point.length > 2 ? point[2] : 0.0)
        .toList();

    final distance = (summary['distance'] as num).toDouble();

    return RouteData(
      coordinates: coords,
      elevations: elevations,
      totalDistance: distance,
    );
  }

  /// Decode an encoded polyline string (Google Polyline Format with optional 3D)
  List<List<double>> _decodePolyline(String encoded, {bool include3D = false}) {
    List<List<double>> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;
    int alt = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;

      // Decode latitude
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;

      // Decode longitude
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      double latitude = lat / 1e5;
      double longitude = lng / 1e5;

      if (include3D && index < len) {
        // Decode altitude/elevation
        shift = 0;
        result = 0;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        int dalt = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
        alt += dalt;
        double altitude = alt / 100.0; // OpenRouteService uses 0.01m precision for elevation

        points.add([latitude, longitude, altitude]);
      } else {
        points.add([latitude, longitude]);
      }
    }

    return points;
  }

  /// Calculate segment distances between waypoints
  List<double> calculateSegmentDistances(List<LatLng> coordinates) {
    final segmentDistances = <double>[];
    const distance = Distance();

    for (int i = 0; i < coordinates.length - 1; i++) {
      final dist = distance.as(
        LengthUnit.Meter,
        coordinates[i],
        coordinates[i + 1],
      );
      segmentDistances.add(dist);
    }

    return segmentDistances;
  }
}

class RouteData {
  final List<LatLng> coordinates;
  final List<double> elevations;
  final double totalDistance;

  RouteData({
    required this.coordinates,
    required this.elevations,
    required this.totalDistance,
  });
}
