import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/models/saved_device.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/services/device_factory.dart';
import 'package:free_ride/services/device_adapter.dart';
import 'package:uuid/uuid.dart';

/// Screen for managing saved workout devices
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _deviceStorage = DeviceStorageService();
  List<SavedDevice> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = _deviceStorage.getAllDevices();
    setState(() {
      _devices = devices;
      _isLoading = false;
    });
  }

  Future<void> _deleteDevice(SavedDevice device) async {
    // Don't allow deleting virtual devices
    if (device.adapterType == 'virtual-bike' || device.adapterType == 'virtual-treadmill') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Virtual devices cannot be deleted')),
      );
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device'),
        content: Text('Are you sure you want to delete "${device.customName}"?'),
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
      await _deviceStorage.deleteDevice(device.id);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${device.customName}"')),
        );
      }
    }
  }

  Future<void> _renameDevice(SavedDevice device) async {
    final controller = TextEditingController(text: device.customName);
    
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Custom Name',
            hintText: 'Enter device name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != device.customName) {
      await _deviceStorage.updateCustomName(device.id, newName);
      await _loadDevices();
    }
  }

  Future<void> _calibrateDevice(SavedDevice device) async {
    final isVirtual = device.adapterType == 'virtual-bike' || device.adapterType == 'virtual-treadmill';
    double calibration = device.powerCalibration;

    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isVirtual ? 'Speed Settings' : 'Power Calibration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isVirtual 
                    ? 'Adjust virtual device speed'
                    : 'Adjust power output multiplier',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isVirtual ? '0 km/h' : '0.5x'),
                  Text(
                    isVirtual 
                        ? '${calibration.toStringAsFixed(0)} km/h'
                        : '${calibration.toStringAsFixed(2)}x',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(isVirtual ? '300 km/h' : '2.0x'),
                ],
              ),
              SizedBox(
                width: 400, // Make slider wider
                child: Slider(
                  value: calibration,
                  min: isVirtual ? 0.0 : 0.5,
                  max: isVirtual ? 300.0 : 2.0,
                  divisions: isVirtual ? 300 : 30,
                  onChanged: (value) {
                    setState(() => calibration = value);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      setState(() => calibration = isVirtual 
                          ? (device.adapterType == 'virtual-bike' ? 30.0 : 15.0)
                          : 1.0);
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, calibration),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result != device.powerCalibration) {
      await _deviceStorage.updatePowerCalibration(device.id, result);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calibration updated')),
        );
      }
    }
  }


  Future<void> _testConnection(SavedDevice device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Testing connection...'),
          ],
        ),
      ),
    );

    final success = await DeviceFactory.testConnection(device);
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
            ? 'Device is available and working'
            : 'Could not connect to device'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _showDiscoveryDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DiscoveryDialog(),
    );
    await _loadDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No devices saved',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to discover devices',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final deviceProvider = context.watch<DeviceProvider>();
                    final isSelected = deviceProvider.selectedDevice?.id == device.id;
                    
                    return _DeviceListTile(
                      device: device,
                      isSelected: isSelected,
                      onTap: () async {
                        await deviceProvider.selectDevice(device);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Selected ${device.displayName}')),
                          );
                        }
                      },
                      onDelete: () => _deleteDevice(device),
                      onRename: () => _renameDevice(device),
                      onCalibrate: () => _calibrateDevice(device),
                      onTest: () => _testConnection(device),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showDiscoveryDialog,
        icon: const Icon(Icons.bluetooth_searching),
        label: const Text('Discover Devices'),
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final SavedDevice device;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onCalibrate;
  final VoidCallback onTest;

  const _DeviceListTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onCalibrate,
    required this.onTest,
  });

  IconData _getDeviceIcon() {
    switch (device.deviceType) {
      case DeviceType.bike:
        return Icons.directions_bike;
      case DeviceType.treadmill:
        return Icons.directions_run;
      case DeviceType.heartRateMonitor:
        return Icons.favorite;
    }
  }

  Color _getDeviceColor() {
    switch (device.adapterType) {
      case 'ftms':
        return Colors.blue;
      case 'echelon':
        return Colors.orange;
      case 'heartrate':
        return Colors.red;
      case 'virtual-bike':
      case 'virtual-treadmill':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getDeviceTypeLabel() {
    switch (device.deviceType) {
      case DeviceType.bike:
        return 'Bike';
      case DeviceType.treadmill:
        return 'Treadmill';
      case DeviceType.heartRateMonitor:
        return 'HR Monitor';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.blue.shade50 : null,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: _getDeviceColor().withOpacity(0.2),
          child: Icon(_getDeviceIcon(), color: _getDeviceColor()),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                device.customName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.bluetoothName,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getDeviceColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getDeviceTypeLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _getDeviceColor(),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${device.shortAddress})',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (device.lastConnected != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Last: ${_formatDate(device.lastConnected!)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'rename':
                onRename();
                break;
              case 'calibrate':
                onCalibrate();
                break;
              case 'test':
                onTest();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'rename',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('Rename'),
                ],
              ),
            ),
            if (device.deviceType != DeviceType.heartRateMonitor)
              const PopupMenuItem(
                value: 'calibrate',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20),
                    SizedBox(width: 12),
                    Text('Calibrate'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'test',
              child: Row(
                children: [
                  Icon(Icons.cable, size: 20),
                  SizedBox(width: 12),
                  Text('Test Connection'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}

class _DiscoveryDialog extends StatefulWidget {
  const _DiscoveryDialog();

  @override
  State<_DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<_DiscoveryDialog> {
  final Map<String, _DiscoveredDeviceInfo> _discoveredDevices = {};
  final _deviceStorage = DeviceStorageService();
  bool _isScanning = true;
  int _remainingSeconds = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _stopDiscovery();
        }
      });
    });
  }

  Future<void> _startDiscovery() async {
    try {
      await DeviceFactory.startDiscovery(
        onDeviceFound: (device, adapterType, deviceType) {
          if (!mounted) return;
          
          setState(() {
            _discoveredDevices[device.remoteId.toString()] = _DiscoveredDeviceInfo(
              bluetoothDevice: device,
              name: device.platformName,
              address: device.remoteId.toString(),
              adapterType: adapterType,
              deviceType: deviceType,
            );
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      
      _stopDiscovery();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  Future<void> _stopDiscovery() async {
    _countdownTimer?.cancel();
    await DeviceFactory.stopDiscovery();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _saveDevice(_DiscoveredDeviceInfo info) async {
    final nameController = TextEditingController(text: info.name);

    final customName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bluetooth Name: ${info.name}'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Custom Name',
                hintText: 'Enter a name for this device',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (customName != null && customName.isNotEmpty) {
      final device = SavedDevice(
        id: const Uuid().v4(),
        bluetoothName: info.name,
        customName: customName,
        address: info.address,
        adapterType: info.adapterType,
        deviceTypeString: info.deviceType == DeviceType.bike 
            ? 'bike' 
            : info.deviceType == DeviceType.treadmill 
              ? 'treadmill' 
              : 'heartRateMonitor',
      );

      await _deviceStorage.saveDevice(device);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$customName"')),
        );
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    DeviceFactory.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('Discover Devices'),
          const Spacer(),
          if (_isScanning)
            Text(
              '$_remainingSeconds s',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (_isScanning)
              const LinearProgressIndicator()
            else
              Container(
                height: 4,
                color: Colors.grey[300],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _discoveredDevices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth_searching,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isScanning 
                              ? 'Searching for devices...' 
                              : 'No devices found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _discoveredDevices.length,
                      itemBuilder: (context, index) {
                        final info = _discoveredDevices.values.elementAt(index);
                        return _DiscoveredDeviceTile(
                          info: info,
                          onSave: () => _saveDevice(info),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (_isScanning)
          TextButton(
            onPressed: _stopDiscovery,
            child: const Text('Stop Discovery'),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
      ],
    );
  }
}

class _DiscoveredDeviceInfo {
  final BluetoothDevice bluetoothDevice;
  final String name;
  final String address;
  final String adapterType;
  final DeviceType deviceType;

  _DiscoveredDeviceInfo({
    required this.bluetoothDevice,
    required this.name,
    required this.address,
    required this.adapterType,
    required this.deviceType,
  });
}

class _DiscoveredDeviceTile extends StatelessWidget {
  final _DiscoveredDeviceInfo info;
  final VoidCallback onSave;

  const _DiscoveredDeviceTile({
    required this.info,
    required this.onSave,
  });

  IconData _getDeviceIcon() {
    switch (info.deviceType) {
      case DeviceType.bike:
        return Icons.directions_bike;
      case DeviceType.treadmill:
        return Icons.directions_run;
      case DeviceType.heartRateMonitor:
        return Icons.favorite;
    }
  }

  Color _getDeviceColor() {
    switch (info.adapterType) {
      case 'ftms':
        return Colors.blue;
      case 'echelon':
        return Colors.orange;
      case 'heartrate':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getDeviceTypeLabel() {
    switch (info.deviceType) {
      case DeviceType.bike:
        return 'Bike';
      case DeviceType.treadmill:
        return 'Treadmill';
      case DeviceType.heartRateMonitor:
        return 'HR Monitor';
    }
  }

  String _getAdapterLabel() {
    switch (info.adapterType) {
      case 'ftms':
        return 'FTMS';
      case 'echelon':
        return 'Echelon';
      case 'heartrate':
        return 'Heart Rate';
      default:
        return info.adapterType.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getDeviceColor().withOpacity(0.2),
        child: Icon(_getDeviceIcon(), color: _getDeviceColor()),
      ),
      title: Text(info.name.isEmpty ? 'Unknown Device' : info.name),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getDeviceColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_getAdapterLabel()} ${_getDeviceTypeLabel()}',
              style: TextStyle(
                fontSize: 11,
                color: _getDeviceColor(),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle),
        color: Colors.green,
        onPressed: onSave,
      ),
    );
  }
}
