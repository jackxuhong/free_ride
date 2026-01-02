import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/models/ride_summary.dart';
import 'package:free_ride/screens/summary_screen.dart';

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
                    );
                  },
                ),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  final RideSummary summary;
  final VoidCallback onTap;

  const _RideHistoryCard({
    required this.summary,
    required this.onTap,
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
        trailing: Icon(
          Icons.chevron_right,
          color: Colors.grey.shade400,
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
