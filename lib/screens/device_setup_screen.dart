import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:free_ride/models/ftms_device.dart' as model;
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/services/ftms_device_service.dart' as ftms_service;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear device cache',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Device Cache'),
                  content: const Text('Are you sure you want to clear the discovered device cache? All devices will be rediscovered and retested on the next scan.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                context.read<DeviceProvider>().clearDeviceCache();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Device cache cleared.')),
                );
              }
            },
          ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, deviceProvider, child) {
          final devices = deviceProvider.availableDevices;
          final selectedId = deviceProvider.selectedDevice?.id;
          final selectedHRMonitorId = deviceProvider.selectedHRMonitor?.id;

          // Separate exercise devices from HR monitors
          final exerciseDevices = devices.where((d) => d.deviceType != model.DeviceType.heartRateMonitor).toList();
          final hrMonitors = devices.where((d) => d.deviceType == model.DeviceType.heartRateMonitor).toList();

          if (devices.isEmpty) {
            return const Center(
              child: Text('No devices available'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              // Exercise Devices Section
              if (exerciseDevices.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Exercise Devices',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                ...exerciseDevices.map((device) {
                  final isSelected = device.id == selectedId;
                  return _buildExerciseDeviceTile(context, deviceProvider, device, isSelected);
                }),
              ],

              // HR Monitors Section (always visible)
              ...[
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'Heart Rate Monitors',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                if (hrMonitors.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'No heart rate monitors found. Tap "Scan for Devices" to discover nearby HR monitors.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  )
                else
                  ...hrMonitors.map((device) {
                    final isSelected = device.id == selectedHRMonitorId;
                    return _buildHRMonitorTile(context, deviceProvider, device, isSelected);
                  }),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startScan(),
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Scan for Devices'),
      ),
    );
  }

  Widget _buildExerciseDeviceTile(BuildContext context, DeviceProvider deviceProvider, model.FTMSDevice device, bool isSelected) {
    return Column(
      children: [
        Card(
          elevation: isSelected ? 4 : 1,
          color: isSelected ? Colors.blue.shade50 : null,
          child: ListTile(
            leading: Icon(
              device.deviceType == model.DeviceType.indoorBike
                ? Icons.directions_bike
                : Icons.directions_run,
              size: 32,
              color: device.deviceType == model.DeviceType.indoorBike
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
              device.deviceType == model.DeviceType.indoorBike
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
              if (context.mounted) {
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
        if (isSelected && device.isVirtual && deviceProvider.selectedDevice != null)
          VirtualDeviceController(device: deviceProvider.selectedDevice!),

        // Show device info if selected and real FTMS device
        if (isSelected && !device.isVirtual && deviceProvider.activeDevice is ftms_service.FTMSDevice)
          Builder(
            builder: (context) {
              final activeDevice = deviceProvider.activeDevice as ftms_service.FTMSDevice;
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
                      if (device.deviceType == model.DeviceType.indoorBike)
                        _InfoRow(
                          icon: Icons.fitness_center,
                          label: 'Resistance Range',
                          value: '${activeDevice.minResistance} - ${activeDevice.maxResistance}',
                        ),
                      if (device.deviceType == model.DeviceType.treadmill)
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
  }

  Widget _buildHRMonitorTile(BuildContext context, DeviceProvider deviceProvider, model.FTMSDevice device, bool isSelected) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.red.shade50 : null,
      child: ListTile(
        leading: const Icon(
          Icons.monitor_heart,
          size: 32,
          color: Colors.red,
        ),
        title: Text(
          device.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: const Text('Heart Rate Monitor'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          if (isSelected) {
            deviceProvider.deselectHRMonitor();
          } else {
            await deviceProvider.selectHRMonitor(device);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isSelected ? 'Deselected ${device.name}' : 'Selected ${device.name}'),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    );
  }

  void _startScan() async {
    final deviceProvider = context.read<DeviceProvider>();

    // Track if user cancelled
    bool cancelled = false;
    // Create a completer to close the dialog when scan completes
    final dialogCompleter = Completer<void>();

    // Start scan immediately (in background)
    Future<void> scanFuture = () async {
      await deviceProvider.startScan();
      if (!cancelled && !dialogCompleter.isCompleted) {
        dialogCompleter.complete();
      }
    }();

    // Show dialog and close it when scan completes or user cancels
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // When scan completes, pop the dialog if still open
        dialogCompleter.future.then((_) {
          if (dialogContext.mounted && Navigator.of(dialogContext, rootNavigator: true).canPop()) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
          }
        });
        return AlertDialog(
          title: const Text('Scanning for Devices'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Looking for BLE devices...'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                deviceProvider.stopScan();
                if (!dialogCompleter.isCompleted) dialogCompleter.complete();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    // Wait for scan to finish if not cancelled
    if (!cancelled) {
      await scanFuture;
      if (mounted) {
        final deviceCount = deviceProvider.availableDevices.where((d) => !d.isVirtual).length;
        if (deviceCount == 0) {
          _showNoDevicesFound(context);
        }
      }
    }
  }
  
  void _showNoDevicesFound(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Devices Found'),
        content: const Text(
          'No compatible devices were found nearby.\n\n'
          'Make sure your device is:\n'
          '• Turned on\n'
          '• In pairing mode\n'
          '• Within Bluetooth range\n\n'
          'Supported: FTMS bikes/treadmills, Echelon bikes,\n'
          'and BLE heart rate monitors.\n\n'
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
  
  void _confirmDeleteDevice(BuildContext context, model.FTMSDevice device) {
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
          Text(
            label,
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(width: 12),
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
  }}