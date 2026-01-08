import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/providers/device_provider.dart';

class VirtualDeviceController extends StatefulWidget {
  final FitnessDevice device;

  const VirtualDeviceController({
    super.key,
    required this.device,
  });

  @override
  State<VirtualDeviceController> createState() => _VirtualDeviceControllerState();
}

class _VirtualDeviceControllerState extends State<VirtualDeviceController> {
  late double _speed;

  @override
  void initState() {
    super.initState();
    _speed = widget.device.effortLevel;
  }

  Future<void> _updateParameters() async {
    final deviceProvider = context.read<DeviceProvider>();
    await deviceProvider.updateDeviceParameters(
      deviceId: widget.device.id,
      effortLevel: _speed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBike = widget.device.deviceType == DeviceType.indoorBike;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Virtual Device Controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            
            // Speed Slider (for both devices)
            Text(
              'Speed: ${_speed.toStringAsFixed(1)} km/h',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: _speed,
              min: 0,
              max: 200,
              divisions: 2000,
              label: '${_speed.toStringAsFixed(1)} km/h',
              onChanged: (value) {
                setState(() => _speed = value);
              },
              onChangeEnd: (value) => _updateParameters(),
            ),
            
            const SizedBox(height: 8),
            Text(
              isBike
                  ? 'Resistance will be automatically controlled by route terrain'
                  : 'Incline will be automatically controlled by route terrain',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
