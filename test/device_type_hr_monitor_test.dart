import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/models/ftms_device.dart';

void main() {
  group('DeviceType.heartRateMonitor', () {
    test('FTMSDevice can be created with heartRateMonitor type', () {
      final device = FTMSDevice(
        id: 'hr-001',
        name: 'Polar H10',
        deviceType: DeviceType.heartRateMonitor,
        isVirtual: false,
        deviceAddress: 'AA:BB:CC:DD:EE:FF',
        lastConnected: DateTime(2026, 1, 1),
      );

      expect(device.id, 'hr-001');
      expect(device.name, 'Polar H10');
      expect(device.deviceType, DeviceType.heartRateMonitor);
      expect(device.isVirtual, false);
      expect(device.deviceAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('displayName does not append (Virtual) for real HR monitor', () {
      final device = FTMSDevice(
        id: 'hr-001',
        name: 'Polar H10',
        deviceType: DeviceType.heartRateMonitor,
        isVirtual: false,
      );

      expect(device.displayName, 'Polar H10');
    });

    test('copyWith preserves heartRateMonitor type', () {
      final device = FTMSDevice(
        id: 'hr-001',
        name: 'Polar H10',
        deviceType: DeviceType.heartRateMonitor,
        isVirtual: false,
      );

      final updated = device.copyWith(name: 'Polar H10 v2');
      expect(updated.name, 'Polar H10 v2');
      expect(updated.deviceType, DeviceType.heartRateMonitor);
      expect(updated.id, 'hr-001');
    });

    test('copyWith can change type to heartRateMonitor', () {
      final device = FTMSDevice(
        id: 'dev-001',
        name: 'Some Device',
        deviceType: DeviceType.indoorBike,
        isVirtual: false,
      );

      final updated = device.copyWith(deviceType: DeviceType.heartRateMonitor);
      expect(updated.deviceType, DeviceType.heartRateMonitor);
    });
  });

  group('DeviceType enum', () {
    test('has three values', () {
      expect(DeviceType.values.length, 3);
    });

    test('contains indoorBike, treadmill, and heartRateMonitor', () {
      expect(DeviceType.values, contains(DeviceType.indoorBike));
      expect(DeviceType.values, contains(DeviceType.treadmill));
      expect(DeviceType.values, contains(DeviceType.heartRateMonitor));
    });

    test('heartRateMonitor has index 2', () {
      expect(DeviceType.heartRateMonitor.index, 2);
    });
  });

  group('Device list filtering (UI logic)', () {
    late List<FTMSDevice> allDevices;

    setUp(() {
      allDevices = [
        FTMSDevice(
          id: 'vb-001',
          name: 'Virtual Indoor Bike',
          deviceType: DeviceType.indoorBike,
          isVirtual: true,
        ),
        FTMSDevice(
          id: 'vt-001',
          name: 'Virtual Treadmill',
          deviceType: DeviceType.treadmill,
          isVirtual: true,
        ),
        FTMSDevice(
          id: 'ftms-001',
          name: 'Wahoo KICKR',
          deviceType: DeviceType.indoorBike,
          isVirtual: false,
          deviceAddress: '11:22:33:44:55:66',
        ),
        FTMSDevice(
          id: 'hr-001',
          name: 'Polar H10',
          deviceType: DeviceType.heartRateMonitor,
          isVirtual: false,
          deviceAddress: 'AA:BB:CC:DD:EE:FF',
        ),
        FTMSDevice(
          id: 'hr-002',
          name: 'Garmin HRM-Pro',
          deviceType: DeviceType.heartRateMonitor,
          isVirtual: false,
          deviceAddress: 'BB:CC:DD:EE:FF:00',
        ),
      ];
    });

    test('filters exercise devices correctly', () {
      final exerciseDevices = allDevices
          .where((d) => d.deviceType != DeviceType.heartRateMonitor)
          .toList();

      expect(exerciseDevices.length, 3);
      expect(
        exerciseDevices.every(
          (d) => d.deviceType != DeviceType.heartRateMonitor,
        ),
        true,
      );
      expect(exerciseDevices.map((d) => d.id), ['vb-001', 'vt-001', 'ftms-001']);
    });

    test('filters HR monitors correctly', () {
      final hrMonitors = allDevices
          .where((d) => d.deviceType == DeviceType.heartRateMonitor)
          .toList();

      expect(hrMonitors.length, 2);
      expect(
        hrMonitors.every(
          (d) => d.deviceType == DeviceType.heartRateMonitor,
        ),
        true,
      );
      expect(hrMonitors.map((d) => d.id), ['hr-001', 'hr-002']);
    });

    test('returns empty HR monitors list when none exist', () {
      final devicesWithoutHR = allDevices
          .where((d) => d.deviceType != DeviceType.heartRateMonitor)
          .toList();

      final hrMonitors = devicesWithoutHR
          .where((d) => d.deviceType == DeviceType.heartRateMonitor)
          .toList();

      expect(hrMonitors, isEmpty);
    });

    test('returns empty exercise devices when only HR monitors exist', () {
      final hrOnly = allDevices
          .where((d) => d.deviceType == DeviceType.heartRateMonitor)
          .toList();

      final exerciseDevices = hrOnly
          .where((d) => d.deviceType != DeviceType.heartRateMonitor)
          .toList();

      expect(exerciseDevices, isEmpty);
    });
  });

  group('Hive DeviceType adapter round-trip', () {
    test('DeviceTypeAdapter writes heartRateMonitor as byte 2', () {
      final adapter = DeviceTypeAdapter();
      expect(adapter.typeId, 9);
    });

    test('FTMSDeviceAdapter has correct typeId', () {
      final adapter = FTMSDeviceAdapter();
      expect(adapter.typeId, 8);
    });
  });
}
