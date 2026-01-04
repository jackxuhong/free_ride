import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/services/location_service.dart';
import 'package:free_ride/services/geocoding_service.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/services/profile_service.dart';
import 'package:free_ride/screens/simulation_screen.dart';
import 'package:free_ride/utils/constants.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  // All locations in order: first is start, last is end, middle are stops
  final List<TextEditingController> _locationControllers = [
    TextEditingController(), // Start
    TextEditingController(), // End
  ];
  final _locationService = LocationService();
  final _geocodingService = GeocodingService();
  final _storageService = RouteStorageService();
  final _profileService = ProfileService();
  final _previewMapController = MapController();
  final _previewMapKey = GlobalKey();

  int? _loadingLocationIndex;
  String? _selectedRouteId;

  @override
  void dispose() {
    for (var controller in _locationControllers) {
      controller.dispose();
    }
    _previewMapController.dispose();
    super.dispose();
  }

  void _addLocation() {
    setState(() {
      // Insert before the last item (end location)
      _locationControllers.insert(_locationControllers.length - 1, TextEditingController());
    });
  }

  void _removeLocation(int index) {
    // Can't remove if only 2 locations (start and end)
    if (_locationControllers.length <= 2) return;
    
    setState(() {
      _locationControllers[index].dispose();
      _locationControllers.removeAt(index);
    });
  }

  void _moveLocationUp(int index) {
    if (index > 0) {
      setState(() {
        final controller = _locationControllers.removeAt(index);
        _locationControllers.insert(index - 1, controller);
      });
    }
  }

  void _moveLocationDown(int index) {
    if (index < _locationControllers.length - 1) {
      setState(() {
        final controller = _locationControllers.removeAt(index);
        _locationControllers.insert(index + 1, controller);
      });
    }
  }

  Future<void> _useCurrentLocation(int index) async {
    setState(() => _loadingLocationIndex = index);

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _geocodingService.reverseGeocode(position);
      _locationControllers[index].text = address;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    } finally {
      setState(() => _loadingLocationIndex = null);
    }
  }

  Future<void> _getRoute() async {
    if (_locationControllers.first.text.isEmpty || _locationControllers.last.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter start and end locations')),
      );
      return;
    }

    try {
      final routeProvider = context.read<RouteProvider>();
      
      // Get waypoints (all locations except first and last)
      final waypoints = _locationControllers.length > 2
          ? _locationControllers.sublist(1, _locationControllers.length - 1)
              .map((c) => c.text)
              .where((text) => text.isNotEmpty)
              .toList()
          : null;
      
      await routeProvider.fetchRoute(
        _locationControllers.first.text,
        _locationControllers.last.text,
        waypointInputs: waypoints,
      );
      
      // Route preview will show automatically when currentRoute is not null
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get route: $e')),
        );
      }
    }
  }

  Future<double> _calculateEstimatedCalories(double distanceKm, double elevationGainM) async {
    // Get user's body weight from profile
    final profile = await _profileService.getProfile();
    final bodyWeightKg = profile?.bodyWeight ?? 70.0; // Default to 70kg if no profile
    
    // Calorie calculation for cycling:
    // - Flat terrain: ~0.5 kcal per kg per km
    // - Elevation gain: ~10 kcal per kg per 100m of elevation
    final flatCalories = bodyWeightKg * distanceKm * 0.5;
    final elevationCalories = bodyWeightKg * (elevationGainM / 100) * 10;
    
    return flatCalories + elevationCalories;
  }

  Future<void> _saveCurrentRoute() async {
    final routeProvider = context.read<RouteProvider>();
    if (routeProvider.currentRoute == null) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Route'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Route Name',
            hintText: 'e.g., Morning Commute',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      try {
        await _storageService.updateRouteName(
          routeProvider.currentRoute!.id,
          name,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Route saved!')),
          );
          setState(() {}); // Refresh dropdown
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save route: $e')),
          );
        }
      }
    }
  }

  void _loadSavedRoute(String routeId) {
    final route = _storageService.getRouteById(routeId);
    if (route == null) return;

    // Clear existing controllers except first 2
    while (_locationControllers.length > 2) {
      _locationControllers.removeLast().dispose();
    }

    // Set start and end
    _locationControllers[0].text = route.startAddress;
    _locationControllers[1].text = route.endAddress;

    // Add waypoints (if any) - insert before end location
    // waypoints are stored in the route, need to get them
    // Since SavedRoute might not have waypoints field, we'll skip for now
    // The route will be loaded into provider which has the waypoint data

    // Load the route into provider
    context.read<RouteProvider>().loadRoute(route);
    
    setState(() {
      _selectedRouteId = routeId;
    });
  }

  Future<Uint8List?> _captureMapScreenshot() async {
    try {
      // Wait a bit to ensure map is fully rendered
      await Future.delayed(const Duration(milliseconds: 100));
      
      final boundary = _previewMapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing map screenshot: $e');
      return null;
    }
  }

  Future<void> _startRide() async {
    final routeProvider = context.read<RouteProvider>();
    if (routeProvider.currentRoute == null) return;
    
    // Capture the route preview as thumbnail
    final thumbnail = await _captureMapScreenshot();
    
    if (mounted) {
      // Initialize ride with thumbnail
      context.read<RideProvider>().initializeRide(
        routeProvider.currentRoute!,
        thumbnail: thumbnail,
      );
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => const SimulationScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RouteProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan Your Ride'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // Saved routes dropdown
                FutureBuilder<List<SavedRoute>>(
                  future: Future.value(_storageService.getAllRoutes()),
                  builder: (context, snapshot) {
                    // Only show routes that have been explicitly saved with a custom name
                    final routes = (snapshot.data ?? [])
                        .where((route) => route.customName != null && route.customName!.isNotEmpty)
                        .toList();
                    if (routes.isEmpty) return const SizedBox.shrink();
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          value: _selectedRouteId,
                          decoration: const InputDecoration(
                            labelText: 'Load Saved Route',
                            prefixIcon: Icon(Icons.bookmark),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select a saved route'),
                          items: routes.map((route) {
                            return DropdownMenuItem<String>(
                              value: route.id,
                              child: Text(route.displayName),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _loadSavedRoute(value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(thickness: 2),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
                
                // Start location
                // All locations section - dynamic labels based on position
                ..._locationControllers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final controller = entry.value;
                  final isFirst = index == 0;
                  final isLast = index == _locationControllers.length - 1;
                  
                  // Determine label and icon
                  String label;
                  IconData icon;
                  if (isFirst) {
                    label = 'Start Location';
                    icon = Icons.location_on;
                  } else if (isLast) {
                    label = 'End Location';
                    icon = Icons.flag;
                  } else {
                    label = 'Stop ${index}';
                    icon = Icons.place;
                  }
                  
                  return Column(
                    children: [
                      if (index > 0) const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: label,
                                hintText: 'Enter address or lat,lng',
                                prefixIcon: Icon(icon),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          
                          // Show move buttons for middle items, location button for all
                          if (!isFirst && !isLast) ...[
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward, size: 20),
                                  onPressed: () => _moveLocationUp(index),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Move up',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_downward, size: 20),
                                  onPressed: () => _moveLocationDown(index),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Move down',
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _removeLocation(index),
                              tooltip: 'Remove stop',
                            ),
                          ] else ...[
                            // Show move buttons for start/end locations
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_upward, size: 20),
                                  onPressed: !isFirst ? () => _moveLocationUp(index) : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Move up',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.arrow_downward, size: 20),
                                  onPressed: !isLast ? () => _moveLocationDown(index) : null,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Move down',
                                ),
                              ],
                            ),
                            IconButton(
                              icon: _loadingLocationIndex == index
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.my_location),
                              onPressed: _loadingLocationIndex == index
                                  ? null
                                  : () => _useCurrentLocation(index),
                              tooltip: 'Use current location',
                            ),
                          ],
                        ],
                      ),
                      
                      // Add dots and button after each item except the last
                      if (!isLast) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: Column(
                                  children: List.generate(
                                    3,
                                    (index) => Container(
                                      margin: const EdgeInsets.symmetric(vertical: 2),
                                      width: 4,
                                      height: 4,
                                      decoration: const BoxDecoration(
                                        color: Colors.grey,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_location),
                              onPressed: _addLocation,
                              tooltip: 'Add Stop',
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                }).toList(),
                const SizedBox(height: 24),
                // Get Route button
                ElevatedButton(
                  onPressed: routeProvider.isLoading ? null : _getRoute,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                  child: routeProvider.isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Get Route', style: TextStyle(fontSize: 16)),
                ),
                
                // Route Preview
                if (routeProvider.currentRoute != null) ...[
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'Route Preview',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  
                  // Route stats
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  const Icon(Icons.straighten, size: 32),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(routeProvider.currentRoute!.geometry.totalDistance / 1000).toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text('Distance'),
                                ],
                              ),
                              Column(
                                children: [
                                  const Icon(Icons.trending_up, size: 32),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${routeProvider.currentRoute!.elevationProfile.totalElevationGain.toStringAsFixed(0)} m',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Text('Elevation Gain'),
                                ],
                              ),
                              FutureBuilder(
                                future: _calculateEstimatedCalories(
                                  routeProvider.currentRoute!.geometry.totalDistance / 1000,
                                  routeProvider.currentRoute!.elevationProfile.totalElevationGain,
                                ),
                                builder: (context, snapshot) {
                                  return Column(
                                    children: [
                                      const Icon(Icons.local_fire_department, size: 32),
                                      const SizedBox(height: 4),
                                      Text(
                                        snapshot.hasData ? '${snapshot.data!.toStringAsFixed(0)} kcal' : '--- kcal',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text('Est. Calories'),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Map preview
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RepaintBoundary(
                      key: _previewMapKey,
                      child: Builder(
                        builder: (context) {
                        // Fit bounds after the map is built
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final waypoints = routeProvider.currentRoute!.coordinates.waypoints
                              .map((point) => point.toLatLng())
                              .toList();
                          if (waypoints.isNotEmpty) {
                            final bounds = LatLngBounds.fromPoints(waypoints);
                            _previewMapController.fitCamera(
                              CameraFit.bounds(
                                bounds: bounds,
                                padding: const EdgeInsets.all(50),
                              ),
                            );
                          }
                        });
                        
                        return FlutterMap(
                          mapController: _previewMapController,
                          options: MapOptions(
                            initialCenter: routeProvider.currentRoute!.coordinates.start,
                            initialZoom: 13,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: AppConstants.osmTileUrl,
                              userAgentPackageName: 'com.example.free_ride',
                            ),
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: routeProvider.currentRoute!.coordinates.waypoints
                                      .map((point) => point.toLatLng())
                                      .toList(),
                                  strokeWidth: 4.0,
                                  color: Colors.blue,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: routeProvider.currentRoute!.coordinates.start,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_on,
                                    size: 40,
                                    color: Colors.green,
                                  ),
                                ),
                                Marker(
                                  point: routeProvider.currentRoute!.coordinates.end,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.flag,
                                    size: 40,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Start Ride button
                  ElevatedButton.icon(
                    onPressed: _startRide,
                    icon: const Icon(Icons.directions_bike),
                    label: const Text('Start Ride'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Save Route button
                  OutlinedButton.icon(
                    onPressed: _saveCurrentRoute,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Save Route'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
                
                if (routeProvider.error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.red.shade900),
                              const SizedBox(width: 8),
                              Text(
                                'Error',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            routeProvider.error ?? '',
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (routeProvider.isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
