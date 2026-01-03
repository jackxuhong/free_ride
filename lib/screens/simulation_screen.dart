import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/screens/summary_screen.dart';
import 'package:free_ride/utils/constants.dart';
import 'package:free_ride/widgets/elevation_chart.dart';
import 'package:free_ride/widgets/elevation_chart.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final _mapController = MapController();
  bool _hasNavigatedToSummary = false;

  @override
  void initState() {
    super.initState();
    // Initialize ride immediately (synchronously) to avoid stale state
    final route = context.read<RouteProvider>().currentRoute;
    if (route != null) {
      context.read<RideProvider>().initializeRide(route);
    }
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
                    initialZoom: AppConstants.defaultMapZoom,
                    minZoom: AppConstants.minMapZoom.toDouble(),
                    maxZoom: AppConstants.maxMapZoom.toDouble(),
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
                // Floating action button on map
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _buildPlayPauseButton(rideProvider),
                ),
              ],
            ),
          ),
          // Stats display
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Speed, elevation, grade
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MetricCard(
                        label: 'Speed',
                        value: '${rideProvider.currentSpeed.toStringAsFixed(1)} km/h',
                        icon: Icons.speed,
                      ),
                      _MetricCard(
                        label: 'Elevation',
                        value: '${rideProvider.currentElevation.toStringAsFixed(0)} m',
                        icon: Icons.terrain,
                      ),
                      _MetricCard(
                        label: 'Grade',
                        value: '${rideProvider.currentGrade.toStringAsFixed(1)}%',
                        icon: Icons.trending_up,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Distance and time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MetricCard(
                        label: 'Distance',
                        value: '${(rideProvider.completedDistance / 1000).toStringAsFixed(2)} km',
                        icon: Icons.straighten,
                      ),
                      _MetricCard(
                        label: 'Time',
                        value: _formatDuration(rideProvider.totalDuration),
                        icon: Icons.timer,
                      ),
                      _MetricCard(
                        label: 'Progress',
                        value: '${rideProvider.completionPercentage.toStringAsFixed(0)}%',
                        icon: Icons.flag,
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Elevation chart
                  ElevationChart(
                    route: route,
                    currentProgress: rideProvider.completionPercentage / 100,
                  ),
                  const SizedBox(height: 8),
                  // Progress bar
                  LinearProgressIndicator(
                    value: rideProvider.completionPercentage / 100,
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(RideProvider rideProvider) {
    if (rideProvider.status == RideStatus.running) {
      return FloatingActionButton(
        onPressed: () => rideProvider.pauseRide(),
        child: const Icon(Icons.pause),
      );
    } else if (rideProvider.status == RideStatus.paused) {
      return FloatingActionButton(
        onPressed: () => rideProvider.resumeRide(),
        backgroundColor: Colors.green,
        child: const Icon(Icons.play_arrow),
      );
    } else {
      return FloatingActionButton(
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

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: Theme.of(context).primaryColor),
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
