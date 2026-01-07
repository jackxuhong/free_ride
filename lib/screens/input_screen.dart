import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:free_ride/models/saved_route.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/services/location_service.dart';
import 'package:free_ride/services/geocoding_service.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/services/profile_service.dart';
import 'package:free_ride/screens/simulation_screen.dart';
import 'package:free_ride/screens/device_setup_screen.dart';
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
  int _routeListRefresh = 0; // Counter to force FutureBuilder refresh
  bool _isRouteEditExpanded = true; // Default expanded for new route
  bool _isRouteValidated = false; // True after Get Route succeeds
  bool _hasUnsavedChanges = false; // True when inputs change after validation
  bool _isRouteSaved = false; // True when Save succeeds

  @override
  void initState() {
    super.initState();
    // Add listeners to track input changes
    for (var controller in _locationControllers) {
      controller.addListener(_onRouteInputChanged);
    }
  }

  void _onRouteInputChanged() {
    if (_isRouteValidated) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

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
      final newController = TextEditingController();
      newController.addListener(_onRouteInputChanged);
      _locationControllers.insert(_locationControllers.length - 1, newController);
      _hasUnsavedChanges = true;
    });
  }

  void _removeLocation(int index) {
    // Can't remove if only 2 locations (start and end)
    if (_locationControllers.length <= 2) return;
    
    setState(() {
      _locationControllers[index].removeListener(_onRouteInputChanged);
      _locationControllers[index].dispose();
      _locationControllers.removeAt(index);
      _hasUnsavedChanges = true;
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
      
      // Route validated successfully
      setState(() {
        _isRouteValidated = true;
        _hasUnsavedChanges = false;
        _isRouteSaved = false; // Route has changed, needs to be saved again
      });
      
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

    // If this is an existing saved route, update it without asking for name
    if (_selectedRouteId != null) {
      try {
        // Get the existing route to keep its custom name
        final existingRoute = _storageService.getRouteById(_selectedRouteId!);
        if (existingRoute?.customName != null) {
          // Delete the old route first (since fetchRoute creates a new ID)
          await _storageService.deleteRoute(_selectedRouteId!);
          
          // Save the new route with the same name
          await _storageService.updateRouteName(
            routeProvider.currentRoute!.id,
            existingRoute!.customName!,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Route updated!')),
            );
            setState(() {
              _isRouteSaved = true;
              _selectedRouteId = routeProvider.currentRoute!.id; // Update to new route ID
              _isRouteEditExpanded = false; // Collapse after save
              _routeListRefresh++; // Force dropdown refresh
            });
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update route: $e')),
          );
        }
        return;
      }
    }

    // For new routes, ask for a name
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
          setState(() {
            _isRouteSaved = true;
            _selectedRouteId = routeProvider.currentRoute!.id;
            _isRouteEditExpanded = false; // Collapse after save
            _routeListRefresh++; // Force dropdown refresh
          });
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

  Future<void> _deleteRoute() async {
    if (_selectedRouteId == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Route'),
        content: const Text('Are you sure you want to delete this saved route?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _storageService.deleteRoute(_selectedRouteId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route deleted')),
        );
        setState(() {
          _selectedRouteId = null;
          _isRouteSaved = false;
          _isRouteValidated = false;
          _isRouteEditExpanded = true;
          _routeListRefresh++; // Force dropdown refresh
          // Clear the current route from provider
          context.read<RouteProvider>().clearRoute();
        });
      }
    }
  }

  void _loadSavedRoute(String routeId) {
    final route = _storageService.getRouteById(routeId);
    if (route == null) return;

    // Clear existing controllers except first 2
    while (_locationControllers.length > 2) {
      final controller = _locationControllers.removeLast();
      controller.removeListener(_onRouteInputChanged);
      controller.dispose();
    }

    // Set start and end
    _locationControllers[0].text = route.startInput;
    _locationControllers[1].text = route.endInput;

    // Add waypoints (if any) - insert before end location
    if (route.waypointInputs != null && route.waypointInputs!.isNotEmpty) {
      for (final waypointInput in route.waypointInputs!) {
        final newController = TextEditingController(text: waypointInput);
        newController.addListener(_onRouteInputChanged);
        _locationControllers.insert(_locationControllers.length - 1, newController);
      }
    }

    // Load the route into provider
    context.read<RouteProvider>().loadRoute(route);
    
    setState(() {
      _selectedRouteId = routeId;
      _isRouteEditExpanded = false; // Collapse edit section
      _isRouteValidated = true; // Already validated
      _isRouteSaved = true; // Already saved
      _hasUnsavedChanges = false;
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
    final deviceProvider = context.read<DeviceProvider>();
    
    if (routeProvider.currentRoute == null) return;
    if (deviceProvider.selectedDevice == null) return;
    
    // Capture the route preview as thumbnail
    final thumbnail = await _captureMapScreenshot();
    
    if (mounted) {
      // Initialize ride with device and thumbnail
      context.read<RideProvider>().startRideWithDevice(
        routeProvider.currentRoute!,
        deviceProvider.activeDevice!,
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
        title: const Text('Plan Your Exercise'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Saved routes dropdown
                FutureBuilder<List<SavedRoute>>(
                  key: ValueKey(_routeListRefresh),
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
                            labelText: 'Create a new route or load a saved one',
                            prefixIcon: Icon(Icons.bookmark),
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('New Route'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('New Route'),
                            ),
                            ...routes.map((route) {
                              return DropdownMenuItem<String>(
                                value: route.id,
                                child: Text(route.displayName),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              // New route selected - reset everything
                              setState(() {
                                _selectedRouteId = null;
                                _isRouteEditExpanded = true;
                                _isRouteValidated = false;
                                _isRouteSaved = false;
                                _hasUnsavedChanges = false;
                                // Clear inputs
                                for (var controller in _locationControllers) {
                                  controller.text = '';
                                }
                                // Remove extra waypoints
                                while (_locationControllers.length > 2) {
                                  final controller = _locationControllers.removeLast();
                                  controller.removeListener(_onRouteInputChanged);
                                  controller.dispose();
                                }
                                // Clear route from provider
                                context.read<RouteProvider>().clearRoute();
                              });
                            } else {
                              _loadSavedRoute(value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
                
                // Collapsible route edit section
                Card(
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: ValueKey(_isRouteEditExpanded),
                      title: const Text('Route Details', style: TextStyle(fontWeight: FontWeight.bold)),
                      initiallyExpanded: _isRouteEditExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          _isRouteEditExpanded = expanded;
                        });
                      },
                      children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
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
                          
                          // Button row: Get Route, Save, Delete
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (routeProvider.isLoading || (!_hasUnsavedChanges && _isRouteValidated))
                                      ? null 
                                      : _getRoute,
                                  icon: routeProvider.isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.route, size: 20),
                                  label: const Text('Get Route'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isRouteValidated && !_isRouteSaved ? _saveCurrentRoute : null,
                                  icon: const Icon(Icons.bookmark_add, size: 20),
                                  label: const Text('Save'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isRouteSaved ? _deleteRoute : null,
                                  icon: const Icon(Icons.delete, size: 20),
                                  label: const Text('Delete'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.all(16),
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey[300],
                                    disabledForegroundColor: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ],
                    ),
                  ),
                ),
                
                // Route Preview
                if (routeProvider.currentRoute != null) ...[

                  const SizedBox(height: 16),
                  
                  // Route stats, device selection, and start button - all in one Card
                  Consumer<DeviceProvider>(
                    builder: (context, deviceProvider, _) {
                      final device = deviceProvider.selectedDevice;
                      final hasDevice = device != null;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Stats row
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.straighten, size: 28),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${(routeProvider.currentRoute!.geometry.totalDistance / 1000).toStringAsFixed(2)} km',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const Text(
                                              'Distance',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: FutureBuilder(
                                      future: _calculateEstimatedCalories(
                                        routeProvider.currentRoute!.geometry.totalDistance / 1000,
                                        routeProvider.currentRoute!.elevationProfile.totalElevationGain,
                                      ),
                                      builder: (context, snapshot) {
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.local_fire_department, size: 28),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  snapshot.hasData ? '${snapshot.data!.toStringAsFixed(0)} kcal' : '--- kcal',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const Text(
                                                  'Est. Calories',
                                                  style: TextStyle(fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 16),
                              // Device and Start button row
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const DeviceSetupScreen(),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        height: 56,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey[300]!),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              device?.deviceType.name == 'indoorBike'
                                                  ? Icons.directions_bike
                                                  : Icons.directions_run,
                                              size: 28,
                                              color: hasDevice ? Colors.green : Colors.grey,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    device?.name ?? 'No device',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  Text(
                                                    device != null
                                                        ? (device.isVirtual ? 'Virtual' : 'Bluetooth')
                                                        : 'Tap to select',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              color: Colors.grey[400],
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: SizedBox(
                                      height: 56,
                                      child: ElevatedButton.icon(
                                        onPressed: hasDevice ? _startRide : null,
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Start'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: Colors.grey[300],
                                          disabledForegroundColor: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
