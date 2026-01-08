import 'package:flutter/material.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/services/device_adapter.dart';

class DeviceConnectionWidget extends StatelessWidget {
  final SavedDevice? device;
  final bool isConnected;

  const DeviceConnectionWidget({
    super.key,
    required this.device,
    this.isConnected = true,
  });

  @override
  Widget build(BuildContext context) {
    if (device == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            device!.deviceType == DeviceType.bike
                ? Icons.directions_bike
                : device!.deviceType == DeviceType.treadmill
                    ? Icons.directions_run
                    : Icons.favorite,
            size: 16,
            color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            device!.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
