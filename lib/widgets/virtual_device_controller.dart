import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/providers/device_provider.dart';

class VirtualDeviceController extends StatefulWidget {
  final FTMSDevice device;

  const VirtualDeviceController({
    super.key,
    required this.device,
  });

  @override
  State<VirtualDeviceController> createState() => _VirtualDeviceControllerState();
}

class _VirtualDeviceControllerState extends State<VirtualDeviceController> {
  late double _effortLevel;
  late double _controllableParam;

  @override
  void initState() {
    super.initState();
    _effortLevel = widget.device.effortLevel;
    _controllableParam = widget.device.controllableParam;
  }

  Future<void> _updateParameters() async {
    final deviceProvider = context.read<DeviceProvider>();
    await deviceProvider.updateDeviceParameters(
      deviceId: widget.device.id,
      effortLevel: _effortLevel,
      controllableParam: _controllableParam,
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
            
            // Effort Level Slider
            Text(
              isBike 
                  ? 'Effort Level: ${_effortLevel.toStringAsFixed(0)}%'
                  : 'Speed: ${_effortLevel.toStringAsFixed(1)} km/h',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: _effortLevel,
              min: 0,
              max: isBike ? 100 : 25,
              divisions: isBike ? 100 : 250,
              label: isBike 
                  ? '${_effortLevel.toStringAsFixed(0)}%'
                  : '${_effortLevel.toStringAsFixed(1)} km/h',
              onChanged: (value) {
                setState(() => _effortLevel = value);
              },
              onChangeEnd: (value) => _updateParameters(),
            ),
            const SizedBox(height: 16),
            
            // Controllable Parameter Slider
            Text(
              isBike
                  ? 'Resistance: ${_controllableParam.toStringAsFixed(0)}'
                  : 'Incline: ${_controllableParam.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              value: _controllableParam,
              min: isBike ? 1 : -3,
              max: isBike ? 20 : 15,
              divisions: isBike ? 19 : 180,
              label: isBike
                  ? _controllableParam.toStringAsFixed(0)
                  : '${_controllableParam.toStringAsFixed(1)}%',
              onChanged: (value) {
                setState(() => _controllableParam = value);
              },
              onChangeEnd: (value) => _updateParameters(),
            ),
            
            const SizedBox(height: 8),
            Text(
              isBike
                  ? 'These controls simulate user pedaling effort and resistance level'
                  : 'Speed is user-controlled. Incline will be auto-adjusted during rides',
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
