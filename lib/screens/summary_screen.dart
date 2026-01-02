import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/models/ride_summary.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/screens/simulation_screen.dart';
import 'package:free_ride/providers/route_provider.dart';

class SummaryScreen extends StatefulWidget {
  final RideSummary summary;

  const SummaryScreen({super.key, required this.summary});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  final _storageService = RouteStorageService();
  bool _isSaving = false;

  Future<void> _saveRide() async {
    setState(() => _isSaving = true);

    try {
      await _storageService.saveRideHistory(widget.summary);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride saved to history')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save ride: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _discardRide() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _repeatRide() async {
    // Reload the route from storage and navigate to simulation screen
    final routeProvider = context.read<RouteProvider>();
    final route = _storageService.getRouteById(widget.summary.routeId);
    
    if (route != null) {
      routeProvider.setCurrentRoute(route);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => SimulationScreen(),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route no longer available')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y h:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Summary'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status banner
            Card(
              color: widget.summary.completed ? Colors.green.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.summary.completed ? Icons.check_circle : Icons.cancel,
                      color: widget.summary.completed ? Colors.green : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.summary.completed ? 'Ride Completed! 🎉' : 'Ride Cancelled',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Route name
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.summary.routeName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dateFormat.format(widget.summary.startTime),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time metrics
            _SectionTitle('Time'),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Total Duration',
                    value: widget.summary.formattedDuration,
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Moving Time',
                    value: _formatDuration(widget.summary.movingTime),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Distance metrics
            _SectionTitle('Distance'),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Completed',
                    value: widget.summary.formattedDistance,
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Progress',
                    value: '${widget.summary.completionPercentage.toStringAsFixed(0)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Speed metrics
            _SectionTitle('Speed'),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Average',
                    value: widget.summary.formattedAverageSpeed,
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Max Speed',
                    value: '${widget.summary.maxSpeed.toStringAsFixed(1)} km/h',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Elevation metrics
            _SectionTitle('Elevation'),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Gain',
                    value: '${widget.summary.totalElevationGain.toStringAsFixed(0)} m',
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Loss',
                    value: '${widget.summary.totalElevationLoss.toStringAsFixed(0)} m',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Max Grade',
                    value: '${widget.summary.maxGrade.toStringAsFixed(1)}%',
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Min Grade',
                    value: '${widget.summary.minGrade.toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Performance metrics
            _SectionTitle('Performance'),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: 'Calories',
                    value: '${widget.summary.caloriesBurned} kcal',
                  ),
                ),
                Expanded(
                  child: _MetricCard(
                    label: 'Avg Power',
                    value: '${widget.summary.averagePower.toStringAsFixed(0)} W',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _discardRide,
                    child: const Text('Discard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _repeatRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Repeat Ride'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveRide,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Ride'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
