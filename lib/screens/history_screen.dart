import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/models/ride_summary.dart';
import 'package:free_ride/screens/summary_screen.dart';
import 'package:free_ride/screens/simulation_screen.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storageService = RouteStorageService();
  List<RideSummary> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    try {
      final history = _storageService.getRideHistory();
      setState(() {
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load history: $e')),
        );
      }
    }
  }

  Future<void> _deleteRide(RideSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ride'),
        content: Text('Delete ride from ${DateFormat('MMM d, y').format(summary.startTime)}?'),
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
      try {
        await _storageService.deleteRideHistory(summary);
        _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Future<void> _renameRide(RideSummary summary) async {
    final controller = TextEditingController(text: summary.routeName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Ride'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Route Name',
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
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != summary.routeName) {
      try {
        await _storageService.updateRideName(summary, newName);
        _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ride renamed')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to rename: $e')),
          );
        }
      }
    }
  }

  Future<void> _continueRide(RideSummary summary) async {
    // Load the route and continue from where it was left off
    final route = _storageService.getRouteById(summary.routeId);
    
    if (route == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route no longer available')),
        );
      }
      return;
    }

    if (mounted) {
      // Import required providers
      final routeProvider = context.read<RouteProvider>();
      final rideProvider = context.read<RideProvider>();
      
      routeProvider.setCurrentRoute(route);
      rideProvider.initializeRide(route);
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SimulationScreen(),
        ),
      );
    }
  }

  Future<void> _restartRide(RideSummary summary) async {
    // Same as continue for now - restart from beginning
    _continueRide(summary);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No ride history yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Complete a ride to see it here',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _history.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    final summary = _history[index];
                    return _RideHistoryCard(
                      summary: summary,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SummaryScreen(summary: summary),
                          ),
                        );
                      },
                      onDelete: () => _deleteRide(summary),
                      onRename: () => _renameRide(summary),
                      onContinue: () => _continueRide(summary),
                      onRestart: () => _restartRide(summary),
                    );
                  },
                ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  final RideSummary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onContinue;
  final VoidCallback onRestart;

  const _RideHistoryCard({
    required this.summary,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onContinue,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, y h:mm a');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: summary.completed ? Colors.green : Colors.orange,
          child: Icon(
            summary.completed ? Icons.check : Icons.cancel,
            color: Colors.white,
          ),
        ),
        title: Text(
          summary.routeName,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(dateFormat.format(summary.startTime)),
            const SizedBox(height: 4),
            Row(
              children: [
                _SmallMetric(
                  icon: Icons.straighten,
                  value: summary.formattedDistance,
                ),
                const SizedBox(width: 16),
                _SmallMetric(
                  icon: Icons.timer,
                  value: summary.formattedDuration,
                ),
                const SizedBox(width: 16),
                _SmallMetric(
                  icon: Icons.speed,
                  value: summary.formattedAverageSpeed,
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'rename') {
              onRename();
            } else if (value == 'delete') {
              onDelete();
            } else if (value == 'continue') {
              onContinue();
            } else if (value == 'restart') {
              onRestart();
            }
          },
          itemBuilder: (context) => [
            if (!summary.completed) ...[
              const PopupMenuItem(
                value: 'continue',
                child: Row(
                  children: [
                    Icon(Icons.play_arrow, size: 20, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Continue'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'restart',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Restart'),
                  ],
                ),
              ),
            ] else
              const PopupMenuItem(
                value: 'restart',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Repeat'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Rename'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  final IconData icon;
  final String value;

  const _SmallMetric({
    required this.icon,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
