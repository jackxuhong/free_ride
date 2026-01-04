import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/models/ftms_device.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/widgets/virtual_device_controller.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, deviceProvider, child) {
          final devices = deviceProvider.availableDevices;
          final selectedId = deviceProvider.selectedDevice?.id;

          if (devices.isEmpty) {
            return const Center(
              child: Text('No devices available'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              final isSelected = device.id == selectedId;

              return Column(
                children: [
                  Card(
                    elevation: isSelected ? 4 : 1,
                    color: isSelected ? Colors.blue.shade50 : null,
                    child: ListTile(
                      leading: Icon(
                        device.deviceType == DeviceType.indoorBike
                            ? Icons.directions_bike
                            : Icons.directions_run,
                        size: 32,
                        color: device.deviceType == DeviceType.indoorBike
                            ? Colors.blue
                            : Colors.orange,
                      ),
                      title: Row(
                        children: [
                          Text(
                            device.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (device.isVirtual) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Virtual',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        device.deviceType == DeviceType.indoorBike
                            ? 'Indoor Bike'
                            : 'Treadmill',
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                      onTap: () async {
                        await deviceProvider.selectDevice(device);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Selected ${device.name}'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  
                  // Show virtual device controller if selected and virtual
                  if (isSelected && device.isVirtual)
                    VirtualDeviceController(device: device),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showScanInfo(context),
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Scan for Devices'),
      ),
    );
  }

  void _showScanInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan for Devices'),
        content: const Text(
          'Bluetooth scanning for real FTMS devices is not yet implemented. '
          'Please use the virtual devices for testing.\n\n'
          'Virtual Bike and Virtual Treadmill are available by default.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
