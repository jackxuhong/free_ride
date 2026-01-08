import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/echelon_data_parser.dart';
import 'package:free_ride/services/echelon_service.dart';
import 'package:free_ride/services/device_factory.dart';

void main() {
  group('EchelonService', () {
    test('can be created with valid FitnessDevice', () {
      final device = FitnessDevice(
        id: 'test-echelon',
        name: 'Echelon Connect Sport',
        deviceType: DeviceType.indoorBike,
        isVirtual: false,
        deviceAddress: 'AA:BB:CC:DD:EE:FF',
      );

      final service = EchelonService(device: device);

      expect(service.deviceType, DeviceType.indoorBike);
      expect(service.minResistance, 1);
      expect(service.maxResistance, 32);
    });

    test('factory creates EchelonService for Echelon devices', () {
      final registry = DeviceFactoryRegistry();

      final device = FitnessDevice(
        id: 'test-echelon',
        name: 'Echelon Connect Sport',
        deviceType: DeviceType.indoorBike,
        isVirtual: false,
        deviceAddress: 'AA:BB:CC:DD:EE:FF',
      );

      final service = registry.createDevice(device);

      expect(service, isA<EchelonService>());
    });
  });

  group('EchelonDataParser', () {
    test('parses valid data packet', () {
      // Sample data packet (simplified)
      final rawData = [0xf0, 0x00, 0x00, 0x0a, 0x00, 0x01, 0x90, 0x03, 0xe8, 0x00, 0x64, 0x00, 0x0a];

      final snapshot = EchelonDataParser.parseData(rawData);

      expect(snapshot.speed, greaterThan(0));
      expect(snapshot.cadenceOrPace, greaterThan(0));
      expect(snapshot.power, greaterThan(0));
      expect(snapshot.controllableParam, 10);
    });

    test('handles empty data gracefully', () {
      final snapshot = EchelonDataParser.parseData([]);

      expect(snapshot.speed, isNull);
      expect(snapshot.cadenceOrPace, isNull);
      expect(snapshot.power, isNull);
    });

    test('handles malformed data gracefully', () {
      final rawData = [0xff, 0xff]; // Too short
      final snapshot = EchelonDataParser.parseData(rawData);

      expect(snapshot.speed, isNull);
      expect(snapshot.cadenceOrPace, isNull);
    });
  });
}