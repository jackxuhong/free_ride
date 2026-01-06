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
  bool _showCompletedBanner = true;

  @override
  void initState() {
    super.initState();
    // Show completed banner once
    if (widget.summary.completed && _showCompletedBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Ride Completed!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          setState(() {
            _showCompletedBanner = false;
          });
        }
      });
    }
  }

  Future<void> _deleteRide() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ride'),
        content: const Text('Are you sure you want to delete this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _storageService.deleteRideHistory(widget.summary);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
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
            // Route thumbnail
            if (widget.summary.routeThumbnail != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  widget.summary.routeThumbnail!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _repeatRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Repeat'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _deleteRide,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
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

            // All metrics in compact grid
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _CompactMetric(label: 'Distance', value: widget.summary.formattedDistance)),
                        Expanded(child: _CompactMetric(label: 'Duration', value: widget.summary.formattedDuration)),
                        Expanded(child: _CompactMetric(label: 'Progress', value: '${widget.summary.completionPercentage.toStringAsFixed(0)}%')),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(child: _CompactMetric(label: 'Avg Speed', value: widget.summary.formattedAverageSpeed)),
                        Expanded(child: _CompactMetric(label: 'Max Speed', value: '${widget.summary.maxSpeed.toStringAsFixed(1)} km/h')),
                        Expanded(child: _CompactMetric(label: 'Calories', value: '${widget.summary.caloriesBurned} kcal')),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        Expanded(child: _CompactMetric(label: 'Elev Gain', value: '${widget.summary.totalElevationGain.toStringAsFixed(0)} m')),
                        Expanded(child: _CompactMetric(label: 'Elev Loss', value: '${widget.summary.totalElevationLoss.toStringAsFixed(0)} m')),
                        Expanded(child: _CompactMetric(label: 'Avg Power', value: '${widget.summary.averagePower.toStringAsFixed(0)} W')),
                      ],
                    ),
                  ],
                ),
              ),
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

class _CompactMetric extends StatelessWidget {
  final String label;
  final String value;

  const _CompactMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
