import 'package:flutter/material.dart';
import 'package:free_ride/models/ftms_device.dart';

class DeviceConnectionWidget extends StatelessWidget {
  final FTMSDevice? device;
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
            device!.deviceType == DeviceType.indoorBike
                ? Icons.directions_bike
                : Icons.directions_run,
            size: 16,
            color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            device!.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ),
          if (device!.isVirtual) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.computer,
              size: 12,
              color: isConnected ? Colors.green.shade700 : Colors.orange.shade700,
            ),
          ],
        ],
      ),
    );
  }
}
