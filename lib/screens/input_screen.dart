import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/services/location_service.dart';
import 'package:free_ride/services/geocoding_service.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/screens/simulation_screen.dart';
import 'package:free_ride/screens/history_screen.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  final _locationService = LocationService();
  final _geocodingService = GeocodingService();
  final _storageService = RouteStorageService();

  bool _isLoadingStart = false;
  bool _isLoadingEnd = false;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
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
      await routeProvider.fetchRoute(
        _startController.text,
        _endController.text,
      );

      if (mounted && routeProvider.currentRoute != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SimulationScreen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get route: $e')),
        );
      }
    }
  }

  Future<void> _repeatLastRide() async {
    final lastRoute = await _storageService.getLastRoute();
    if (lastRoute == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No previous route found')),
        );
      }
      return;
    }

    if (mounted) {
      context.read<RouteProvider>().loadRoute(lastRoute);
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
        title: const Text('Free Ride'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const HistoryScreen(),
                ),
              );
            },
            tooltip: 'Ride History',
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
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
                // End location
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
                const SizedBox(height: 16),
                // Repeat Last Ride button
                OutlinedButton.icon(
                  onPressed: _repeatLastRide,
                  icon: const Icon(Icons.replay),
                  label: const Text('Repeat Last Ride'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
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
