import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/screens/summary_screen.dart';
import 'package:free_ride/utils/constants.dart';
import 'package:free_ride/widgets/elevation_chart.dart';
import 'package:free_ride/widgets/device_connection_widget.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final _mapController = MapController();
  bool _hasNavigatedToSummary = false;
  bool _isNavigationMode = true; // Navigation mode on by default
  bool _autoFollow = true; // Track if auto-follow is enabled

  @override
  void initState() {
    super.initState();
    // Ride should already be initialized with thumbnail from input screen
    // No need to re-initialize here
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _toggleNavigationMode() {
    setState(() {
      _isNavigationMode = !_isNavigationMode;
    });
  }

  void _recenterMap() {
    setState(() {
      _autoFollow = true;
    });
  }

  void _showIntensityControl(BuildContext context, RideProvider rideProvider) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Workout Intensity',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${rideProvider.workoutIntensity.toStringAsFixed(1)}×',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: rideProvider.workoutIntensity,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${rideProvider.workoutIntensity.toStringAsFixed(1)}×',
                    onChanged: (value) {
                      setState(() {
                        rideProvider.setWorkoutIntensity(value);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0.5× (Easy)', style: TextStyle(color: Colors.grey[600])),
                      Text('2.0× (Hard)', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showCancelDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('End Ride Early?'),
            content: const Text(
              'Your progress will be saved. You can view your stats on the summary screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Continue Riding'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('End Ride'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _cancelRide() async {
    final confirmed = await _showCancelDialog();
    if (!confirmed || !mounted) return;

    final rideProvider = context.read<RideProvider>();
    final summary = await rideProvider.cancelRide();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => SummaryScreen(summary: summary),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeProvider = context.watch<RouteProvider>();
    final rideProvider = context.watch<RideProvider>();
    final route = routeProvider.currentRoute;

    if (route == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Simulation')),
        body: const Center(child: Text('No route loaded')),
      );
    }

    // Always center map on current position if auto-follow is enabled
    if (_autoFollow && rideProvider.currentPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Set rotation based on navigation mode
          final rotation = _isNavigationMode ? -rideProvider.currentBearing : 0.0;
          _mapController.moveAndRotate(
            rideProvider.currentPosition!,
            16.0, // Always use zoom level 16
            rotation,
          );
        }
      });
    }

    // Check if ride completed (but only if it was actually started)
    if (rideProvider.status == RideStatus.completed && 
        rideProvider.startTime != null && 
        !_hasNavigatedToSummary) {
      _hasNavigatedToSummary = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          final summary = await rideProvider.completeRide();
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => SummaryScreen(summary: summary),
              ),
            );
          }
        }
      });
    }

    // Convert waypoints to LatLng
    final waypoints = route.coordinates.waypoints
        .map((point) => point.toLatLng())
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(route.displayName),
        actions: [
          // Device connection badge
          if (rideProvider.activeDevice != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: DeviceConnectionWidget(
                  device: context.read<DeviceProvider>().selectedDevice!,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: _cancelRide,
            tooltip: 'Cancel Ride',
          ),
        ],
      ),
      body: Column(
        children: [
          // Map with floating button
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: route.coordinates.start,
                    initialZoom: 16.0,
                    minZoom: AppConstants.minMapZoom.toDouble(),
                    maxZoom: AppConstants.maxMapZoom.toDouble(),
                    onMapEvent: (event) {
                      // Detect manual map interaction
                      if (_autoFollow && 
                          (event is MapEventMove || event is MapEventRotate) &&
                          event.source == MapEventSource.mapController) {
                        // Allow programmatic moves
                        return;
                      }
                      if (_autoFollow && 
                          (event is MapEventMove || event is MapEventRotate) &&
                          event.source != MapEventSource.mapController) {
                        // User manually moved/rotated the map
                        setState(() {
                          _autoFollow = false;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: AppConstants.osmTileUrl,
                      userAgentPackageName: 'com.example.free_ride',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: waypoints,
                          strokeWidth: 4.0,
                          color: Colors.blue,
                        ),
                      ],
                    ),
                    if (rideProvider.currentPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: rideProvider.currentPosition!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.directions_bike,
                              size: 40,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // Floating buttons on map
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Recenter button (shown when auto-follow is off)
                      if (!_autoFollow)
                        FloatingActionButton(
                          heroTag: 'recenter',
                          onPressed: _recenterMap,
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.blue,
                          child: const Icon(Icons.my_location),
                        ),
                      if (!_autoFollow) const SizedBox(height: 8),
                      // Navigation mode toggle
                      FloatingActionButton(
                        heroTag: 'navigation',
                        onPressed: _toggleNavigationMode,
                        backgroundColor: _isNavigationMode ? Colors.blue : Colors.white,
                        foregroundColor: _isNavigationMode ? Colors.white : Colors.grey,
                        child: Icon(
                          _isNavigationMode ? Icons.navigation : Icons.navigation_outlined,
                        ),
                      ),
                      // Intensity control (for device rides)
                      if (rideProvider.activeDevice != null) ...[
                        const SizedBox(height: 8),
                        FloatingActionButton(
                          heroTag: 'intensity',
                          onPressed: () => _showIntensityControl(context, rideProvider),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          child: const Icon(Icons.fitness_center),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Play/pause button
                      _buildPlayPauseButton(rideProvider),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Stats panel - fixed height, scales width only
          Container(
            height: 335,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Speed, elevation, grade
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Speed',
                        value: '${rideProvider.currentSpeed.toStringAsFixed(1)} km/h',
                        icon: Icons.speed,
                      ),
                    ),
                    Expanded(
                      child: _MetricCard(
                        label: 'Elevation',
                        value: '${rideProvider.currentElevation.toStringAsFixed(0)} m',
                        icon: Icons.terrain,
                      ),
                    ),
                    Expanded(
                      child: _MetricCard(
                        label: 'Grade',
                        value: '${rideProvider.currentGrade.toStringAsFixed(1)}%',
                        icon: Icons.trending_up,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Distance and time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Distance',
                        value: '${(rideProvider.completedDistance / 1000).toStringAsFixed(2)} km',
                        icon: Icons.straighten,
                      ),
                    ),
                    Expanded(
                      child: _MetricCard(
                        label: 'Time',
                        value: _formatDuration(rideProvider.totalDuration),
                        icon: Icons.timer,
                      ),
                    ),
                    Expanded(
                      child: _MetricCard(
                        label: 'Progress',
                        value: '${rideProvider.completionPercentage.toStringAsFixed(0)}%',
                        icon: Icons.flag,
                      ),
                    ),
                  ],
                ),
                // Show device metrics if available
                if (rideProvider.currentHeartRate > 0 || rideProvider.activeDevice != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Calories',
                          value: '${rideProvider.currentCalories.toStringAsFixed(0)} kcal',
                          icon: Icons.local_fire_department,
                          color: Colors.orange,
                        ),
                      ),
                      if (rideProvider.currentHeartRate > 0)
                        Expanded(
                          child: _MetricCard(
                            label: 'Heart Rate',
                            value: '${rideProvider.currentHeartRate.toStringAsFixed(0)} bpm',
                            icon: Icons.favorite,
                            color: Colors.red,
                          ),
                        ),
                      if (rideProvider.activeDevice != null)
                        Expanded(
                          child: _MetricCard(
                            label: 'Intensity',
                            value: '${rideProvider.workoutIntensity.toStringAsFixed(1)}×',
                            icon: Icons.fitness_center,
                            color: Colors.blue,
                          ),
                        ),
                    ],
                  ),
                ],
                const Spacer(),
                // Elevation chart - fixed height
                SizedBox(
                  height: 70,
                  child: ElevationChart(
                    route: route,
                    currentProgress: rideProvider.completionPercentage / 100,
                  ),
                ),
                const SizedBox(height: 4),
                // Progress bar - fixed height
                LinearProgressIndicator(
                  value: rideProvider.completionPercentage / 100,
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(RideProvider rideProvider) {
    if (rideProvider.status == RideStatus.running) {
      return FloatingActionButton(
        heroTag: 'playPause',
        onPressed: () => rideProvider.pauseRide(),
        child: const Icon(Icons.pause),
      );
    } else if (rideProvider.status == RideStatus.paused) {
      return FloatingActionButton(
        heroTag: 'playPause',
        onPressed: () => rideProvider.resumeRide(),
        backgroundColor: Colors.green,
        child: const Icon(Icons.play_arrow),
      );
    } else {
      return FloatingActionButton(
        heroTag: 'playPause',
        onPressed: () => rideProvider.startRide(),
        backgroundColor: Colors.green,
        child: const Icon(Icons.play_arrow),
      );
    }
  }

  String _formatDuration(Duration duration) {
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

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: color ?? Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
