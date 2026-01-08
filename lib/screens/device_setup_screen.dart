import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/services/ftms_service.dart';
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
        title: const Text('Manage Devices'),
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!device.isVirtual)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _confirmDeleteDevice(context, device),
                            ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.green)
                          else
                            const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                        ],
                      ),
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
                  
                  // Show device info if selected and real FTMS device
                  if (isSelected && !device.isVirtual && deviceProvider.activeDevice != null)
                    Builder(
                      builder: (context) {
                        final activeDevice = deviceProvider.activeDevice;
                        if (activeDevice is! FTMSService) {
                          return const SizedBox.shrink();
                        }
                        
                        return Card(
                          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Device Capabilities',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _InfoRow(
                                  icon: Icons.bluetooth,
                                  label: 'Connection',
                                  value: activeDevice.isConnected ? 'Connected' : 'Disconnected',
                                  valueColor: activeDevice.isConnected ? Colors.green : Colors.orange,
                                ),
                                if (device.deviceType == DeviceType.indoorBike)
                                  _InfoRow(
                                    icon: Icons.fitness_center,
                                    label: 'Resistance Range',
                                    value: '${activeDevice.minResistance} - ${activeDevice.maxResistance}',
                                  ),
                                if (device.deviceType == DeviceType.treadmill)
                                  _InfoRow(
                                    icon: Icons.terrain,
                                    label: 'Incline Range',
                                    value: '${activeDevice.minIncline.toStringAsFixed(1)}% - ${activeDevice.maxIncline.toStringAsFixed(1)}%',
                                  ),
                                if (device.deviceAddress != null)
                                  _InfoRow(
                                    icon: Icons.fingerprint,
                                    label: 'Device ID',
                                    value: device.deviceAddress!.substring(0, 17),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startScan(context),
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Scan for Devices'),
      ),
    );
  }

  void _startScan(BuildContext context) async {
    final deviceProvider = context.read<DeviceProvider>();
    
    // Request necessary permissions first
    final permissionsGranted = await _requestPermissions(context);
    if (!permissionsGranted) {
      return;
    }
    
    // Show scanning dialog with cancel button
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scanning for Devices'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Looking for fitness devices...'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    // Start scanning
    await deviceProvider.startScan();
    
    // Close dialog if still showing
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst || !route.willHandlePopInternally);
      
      // Show result
      final deviceCount = deviceProvider.availableDevices.where((d) => !d.isVirtual).length;
      if (deviceCount == 0) {
        _showNoDevicesFound(context);
      }
    }
  }

  Future<bool> _requestPermissions(BuildContext context) async {
    try {
      // Request location permission (required for Bluetooth scanning on iOS/Android)
      var locationStatus = await Permission.location.status;
      if (locationStatus.isDenied || locationStatus.isRestricted) {
        locationStatus = await Permission.location.request();
        if (locationStatus.isPermanentlyDenied) {
          _showPermissionDeniedDialog(context, 'Location');
          return false;
        }
      }

      // Request Bluetooth permissions where available
      try {
        if (await Permission.bluetooth.isRestricted || await Permission.bluetooth.isDenied) {
          final bluetoothStatus = await Permission.bluetooth.request();
          if (bluetoothStatus.isPermanentlyDenied) {
            _showPermissionDeniedDialog(context, 'Bluetooth');
            return false;
          }
        }
      } catch (e) {
        // Bluetooth permission might not be available on all platforms
        print('Bluetooth permission not available: $e');
      }

      // On Android, also request Bluetooth scan/connect permissions
      try {
        if (await Permission.bluetoothScan.isRestricted || await Permission.bluetoothScan.isDenied) {
          final scanStatus = await Permission.bluetoothScan.request();
          if (scanStatus.isPermanentlyDenied) {
            _showPermissionDeniedDialog(context, 'Bluetooth Scan');
            return false;
          }
        }
      } catch (e) {
        // Bluetooth scan permission might not be available on all platforms
        print('Bluetooth scan permission not available: $e');
      }

      try {
        if (await Permission.bluetoothConnect.isRestricted || await Permission.bluetoothConnect.isDenied) {
          final connectStatus = await Permission.bluetoothConnect.request();
          if (connectStatus.isPermanentlyDenied) {
            _showPermissionDeniedDialog(context, 'Bluetooth Connect');
            return false;
          }
        }
      } catch (e) {
        // Bluetooth connect permission might not be available on all platforms
        print('Bluetooth connect permission not available: $e');
      }

      return true;
    } catch (e) {
      // If permission handling fails completely, show error but allow scan to proceed
      // Only log in debug mode, don't print to console in production
      if (e.toString().contains('MissingPluginException')) {
        // This is expected during hot reload, don't show dialog
        // Just allow scan to proceed
      } else {
        _showPermissionErrorDialog(context, e.toString());
      }
      return true; // Allow scan to proceed even if permissions fail
    }
  }

  void _showPermissionErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission System Unavailable'),
        content: Text(
          'The permission system is not available right now.\n\n'
          'Error: $error\n\n'
          'Scanning will proceed, but you may need to grant permissions manually '
          'in your device settings for Bluetooth to work properly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog(BuildContext context, String permissionType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$permissionType Permission Required'),
        content: Text(
          '$permissionType permission is required for Bluetooth device scanning.\n\n'
          'Please go to your device settings and enable $permissionType permission for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
  
  void _showNoDevicesFound(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Devices Found'),
        content: const Text(
          'No fitness devices were found nearby.\n\n'
          'Supported devices include:\n'
          '• FTMS compatible equipment\n'
          '• Echelon Connect Sport bikes\n\n'
          'Make sure your device is:\n'
          '• Turned on\n'
          '• In pairing mode\n'
          '• Within Bluetooth range\n\n'
          'You can use virtual devices for testing.',
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
  
  void _confirmDeleteDevice(BuildContext context, FitnessDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Remove "${device.name}" from your device list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await context.read<DeviceProvider>().removeDevice(device.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Removed ${device.name}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
