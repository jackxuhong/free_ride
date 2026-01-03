import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/providers/route_provider.dart';
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
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final List<TextEditingController> _waypointControllers = [];
  final _locationService = LocationService();
  final _geocodingService = GeocodingService();
  final _storageService = RouteStorageService();
  final _profileService = ProfileService();

  bool _isLoadingStart = false;
  bool _isLoadingEnd = false;
  String? _selectedRouteId;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    for (var controller in _waypointControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addWaypoint() {
    setState(() {
      _waypointControllers.add(TextEditingController());
    });
  }

  void _removeWaypoint(int index) {
    setState(() {
      _waypointControllers[index].dispose();
      _waypointControllers.removeAt(index);
    });
  }

  void _moveWaypointUp(int index) {
    if (index > 0) {
      setState(() {
        final controller = _waypointControllers.removeAt(index);
        _waypointControllers.insert(index - 1, controller);
      });
    }
  }

  void _moveWaypointDown(int index) {
    if (index < _waypointControllers.length - 1) {
      setState(() {
        final controller = _waypointControllers.removeAt(index);
        _waypointControllers.insert(index + 1, controller);
      });
    }
  }

  Future<void> _useCurrentLocationForStart() async {
    setState(() => _isLoadingStart = true);

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _geocodingService.reverseGeocode(position);
      _startController.text = address;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    } finally {
      setState(() => _isLoadingStart = false);
    }
  }

  Future<void> _useCurrentLocationForEnd() async {
    setState(() => _isLoadingEnd = true);

    try {
      final position = await _locationService.getCurrentPosition();
      final address = await _geocodingService.reverseGeocode(position);
      _endController.text = address;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    } finally {
      setState(() => _isLoadingEnd = false);
    }
  }

  Future<void> _getRoute() async {
    if (_startController.text.isEmpty || _endController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter start and end locations')),
      );
      return;
    }

    try {
      final routeProvider = context.read<RouteProvider>();
      
      // Get waypoint addresses
      final waypoints = _waypointControllers
          .map((c) => c.text)
          .where((text) => text.isNotEmpty)
          .toList();
      
      await routeProvider.fetchRoute(
        _startController.text,
        _endController.text,
        waypointInputs: waypoints.isNotEmpty ? waypoints : null,
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

    // Populate fields
    _startController.text = route.startAddress;
    _endController.text = route.endAddress;

    // Clear existing waypoints
    for (var controller in _waypointControllers) {
      controller.dispose();
    }
    _waypointControllers.clear();

    // Load the route into provider
    context.read<RouteProvider>().loadRoute(route);
    
    setState(() {
      _selectedRouteId = routeId;
    });
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        decoration: const InputDecoration(
                          labelText: 'Start Location',
                          hintText: 'Enter address or lat,lng',
                          prefixIcon: Icon(Icons.location_on),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isLoadingStart
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      onPressed: _isLoadingStart ? null : _useCurrentLocationForStart,
                      tooltip: 'Use current location',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Waypoints section
                ..._waypointControllers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final controller = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: 'Stop ${index + 1}',
                              hintText: 'Enter address',
                              prefixIcon: const Icon(Icons.place),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 20),
                              onPressed: index > 0 ? () => _moveWaypointUp(index) : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 20),
                              onPressed: index < _waypointControllers.length - 1
                                  ? () => _moveWaypointDown(index)
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => _removeWaypoint(index),
                          tooltip: 'Remove stop',
                        ),
                      ],
                    ),
                  );
                }).toList(),
                
                // Add waypoint button
                OutlinedButton.icon(
                  onPressed: _addWaypoint,
                  icon: const Icon(Icons.add_location),
                  label: const Text('Add Stop'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                  ),
                ),
                
                // End location
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _endController,
                        decoration: const InputDecoration(
                          labelText: 'End Location',
                          hintText: 'Enter address or lat,lng',
                          prefixIcon: Icon(Icons.flag),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isLoadingEnd
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      onPressed: _isLoadingEnd ? null : _useCurrentLocationForEnd,
                      tooltip: 'Use current location',
                    ),
                  ],
                ),
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
                    child: FlutterMap(
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
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Start Ride button
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SimulationScreen(),
                        ),
                      );
                    },
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
