import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:free_ride/utils/constants.dart';
import 'package:free_ride/services/profile_service.dart';

class GeocodingService {
  static final GeocodingService _instance = GeocodingService._internal();
  factory GeocodingService() => _instance;
  GeocodingService._internal();

  final _profileService = ProfileService();
  DateTime? _lastNominatimCall;

  /// Geocode an address or coordinate string to LatLng
  Future<LatLng> geocode(String input) async {
    // Check if input is already in coordinate format (lat,lng)
    if (_isCoordinateFormat(input)) {
      return _parseCoordinates(input);
    }

    // Try native geocoding first (skip on macOS as it's unreliable)
    if (!Platform.isMacOS) {
      try {
        return await _geocodeWithNative(input);
      } catch (e) {
        developer.log('Native geocoding failed: $e', name: 'GeocodingService', level: 900, error: e);
        // Fall through to Nominatim
      }
    }

    // Use Nominatim
    try {
      return await _geocodeWithNominatim(input);
    } catch (nominatimError) {
      developer.log('Nominatim geocoding failed: $nominatimError', name: 'GeocodingService', level: 900, error: nominatimError);
      rethrow;
    }
  }

  /// Check if input is in coordinate format
  bool _isCoordinateFormat(String input) {
    final coordPattern = RegExp(r'^-?\d+\.?\d*,\s*-?\d+\.?\d*$');
    return coordPattern.hasMatch(input.trim());
  }

  /// Parse coordinate string to LatLng
  LatLng _parseCoordinates(String input) {
    final parts = input.trim().split(',');
    final lat = double.parse(parts[0].trim());
    final lng = double.parse(parts[1].trim());
    return LatLng(lat, lng);
  }

  /// Geocode using native platform services
  Future<LatLng> _geocodeWithNative(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) {
        throw Exception('No location found for address: $address');
      }
      final location = locations.first;
      if (location.latitude == null || location.longitude == null) {
        throw Exception('Invalid coordinates returned for address: $address');
      }
      return LatLng(location.latitude, location.longitude);
    } catch (e) {
      throw Exception('Native geocoding failed: $e');
    }
  }

  /// Geocode using Nominatim API as fallback
  Future<LatLng> _geocodeWithNominatim(String address) async {
    // Respect rate limiting
    if (_lastNominatimCall != null) {
      final timeSinceLastCall = DateTime.now().difference(_lastNominatimCall!);
      if (timeSinceLastCall < AppConstants.nominatimRateLimit) {
        await Future.delayed(
          AppConstants.nominatimRateLimit - timeSinceLastCall,
        );
      }
    }

    final url = Uri.parse(
      '${AppConstants.nominatimBaseUrl}/search?'
      'q=${Uri.encodeComponent(address)}&format=json&limit=1',
    );

    // Get user agent with email from profile
    final profile = await _profileService.getProfile();
    final userAgent = profile?.email != null && profile!.email.isNotEmpty
        ? AppConstants.getUserAgent(profile.email)
        : AppConstants.nominatimUserAgent;

    final response = await http.get(
      url,
      headers: {
        'User-Agent': userAgent,
      },
    );

    _lastNominatimCall = DateTime.now();

    if (response.statusCode == 200) {
      final List results = json.decode(response.body);
      if (results.isNotEmpty) {
        final result = results[0];
        return LatLng(
          double.parse(result['lat']),
          double.parse(result['lon']),
        );
      }
    }

    throw Exception('Geocoding failed for address: $address');
  }

  /// Reverse geocode coordinates to address
  Future<String> reverseGeocode(LatLng latLng) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final parts = <String>[];

        if (placemark.street != null && placemark.street!.isNotEmpty) {
          parts.add(placemark.street!);
        }
        if (placemark.locality != null && placemark.locality!.isNotEmpty) {
          parts.add(placemark.locality!);
        }
        if (placemark.administrativeArea != null &&
            placemark.administrativeArea!.isNotEmpty) {
          parts.add(placemark.administrativeArea!);
        }
        if (placemark.country != null && placemark.country!.isNotEmpty) {
          parts.add(placemark.country!);
        }

        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (e) {
      // Fall back to coordinate string if reverse geocoding fails
    }

    return '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
  }
}
