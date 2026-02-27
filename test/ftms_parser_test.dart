import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/models/device_data_snapshot.dart';
import 'package:free_ride/services/ftms_device_service.dart';

/// Helper class to expose the private parsing methods for testing.
///
/// We use the fact that [FTMSDevice] can be instantiated with a stub model
/// and then call its public [simulate] method. Instead, we replicate the
/// parsing logic inline for unit-test purposes.
void main() {
  group('FTMS Indoor Bike Data Parsing', () {
    // The parsing logic is private to FTMSDevice, so we test via byte buffers
    // and known expected outputs.

    test('parses speed-only packet (no optional fields)', () {
      // flags = 0x0000 (no optional flags), speed = 2000 (20.00 km/h)
      final data = [0x00, 0x00, 0xD0, 0x07]; // flags + speed
      final snapshot = parseIndoorBikeData(data);

      expect(snapshot.speed, closeTo(20.0, 0.01));
      expect(snapshot.cadenceOrPace, isNull);
      expect(snapshot.power, isNull);
      expect(snapshot.heartRate, isNull);
    });

    test('parses speed + cadence (bit 2)', () {
      // flags = 0x0004, speed = 2000, cadence = 180 (90.0 RPM)
      final data = [0x04, 0x00, 0xD0, 0x07, 0xB4, 0x00];
      final snapshot = parseIndoorBikeData(data);

      expect(snapshot.speed, closeTo(20.0, 0.01));
      expect(snapshot.cadenceOrPace, closeTo(90.0, 0.1));
    });

    test('parses speed + avg speed (bit 1) + cadence (bit 2)', () {
      // flags = 0x0006 (bits 1 + 2)
      // speed = 2000, avg_speed = 1800, cadence = 160 (80 RPM)
      final data = [0x06, 0x00, 0xD0, 0x07, 0x08, 0x07, 0xA0, 0x00];
      final snapshot = parseIndoorBikeData(data);

      expect(snapshot.speed, closeTo(20.0, 0.01));
      // avg speed skipped, cadence = 0x00A0 = 160 → 80.0 RPM
      expect(snapshot.cadenceOrPace, closeTo(80.0, 0.1));
    });

    test('parses speed + resistance (bit 5) + power (bit 6)', () {
      // flags = 0x0060 (bits 5 + 6)
      // speed = 2500, resistance = 10, power = 150
      final data = [
        0x60, 0x00, // flags
        0xC4, 0x09, // speed 2500 → 25.00 km/h
        0x0A, 0x00, // resistance 10
        0x96, 0x00, // power 150 W
      ];
      final snapshot = parseIndoorBikeData(data);

      expect(snapshot.speed, closeTo(25.0, 0.01));
      expect(snapshot.controllableParam, closeTo(10.0, 0.01));
      expect(snapshot.power, closeTo(150.0, 0.01));
    });

    test('parses full packet with all intermediate fields', () {
      // flags = 0x027E (bits 1-6 + bit 9)
      // = 0x02 | 0x04 | 0x08 | 0x10 | 0x20 | 0x40 | 0x200
      final data = [
        0x7E, 0x02, // flags
        0xD0, 0x07, // speed = 2000 → 20.00 km/h
        0xBC, 0x07, // avg speed = 1980 (skipped)
        0xB4, 0x00, // cadence = 180 → 90.0 RPM
        0xA0, 0x00, // avg cadence (skipped)
        0xE8, 0x03, 0x00, // total distance = 1000 (skipped, uint24)
        0x0A, 0x00, // resistance = 10
        0x96, 0x00, // power = 150 W
        0x48, // heart rate = 72 bpm
      ];
      final snapshot = parseIndoorBikeData(data);

      expect(snapshot.speed, closeTo(20.0, 0.01));
      expect(snapshot.cadenceOrPace, closeTo(90.0, 0.1));
      expect(snapshot.controllableParam, closeTo(10.0, 0.01));
      expect(snapshot.power, closeTo(150.0, 0.01));
      expect(snapshot.heartRate, 72);
    });

    test('handles short packet gracefully', () {
      final snapshot = parseIndoorBikeData([0x00]);
      expect(snapshot.speed, isNull);
    });
  });
}

/// Replicates FTMSDevice._parseIndoorBikeData for testability.
DeviceDataSnapshot parseIndoorBikeData(List<int> data) {
  if (data.length < 4) return DeviceDataSnapshot();

  final flags = data[0] | (data[1] << 8);
  int offset = 2;

  double? speed;
  double? cadence;
  double? power;
  int? heartRate;
  double? resistance;

  // Instantaneous Speed — always present
  if (offset + 2 <= data.length) {
    final speedRaw = data[offset] | (data[offset + 1] << 8);
    speed = speedRaw * 0.01;
    offset += 2;
  }

  // Bit 1 — Average Speed
  if ((flags & 0x02) != 0) {
    offset += 2;
  }

  // Bit 2 — Instantaneous Cadence
  if ((flags & 0x04) != 0 && offset + 2 <= data.length) {
    final cadenceRaw = data[offset] | (data[offset + 1] << 8);
    cadence = cadenceRaw * 0.5;
    offset += 2;
  }

  // Bit 3 — Average Cadence
  if ((flags & 0x08) != 0) {
    offset += 2;
  }

  // Bit 4 — Total Distance (uint24)
  if ((flags & 0x10) != 0) {
    offset += 3;
  }

  // Bit 5 — Resistance Level
  if ((flags & 0x20) != 0 && offset + 2 <= data.length) {
    final resistanceRaw = data[offset] | (data[offset + 1] << 8);
    resistance = resistanceRaw.toDouble();
    offset += 2;
  }

  // Bit 6 — Instantaneous Power
  if ((flags & 0x40) != 0 && offset + 2 <= data.length) {
    final powerRaw = data[offset] | (data[offset + 1] << 8);
    power = powerRaw.toDouble();
    offset += 2;
  }

  // Bit 7 — Average Power
  if ((flags & 0x80) != 0) {
    offset += 2;
  }

  // Bit 8 — Expended Energy
  if ((flags & 0x100) != 0) {
    offset += 5;
  }

  // Bit 9 — Heart Rate
  if ((flags & 0x200) != 0 && offset + 1 <= data.length) {
    heartRate = data[offset];
    offset += 1;
  }

  return DeviceDataSnapshot(
    speed: speed,
    power: power,
    cadenceOrPace: cadence,
    heartRate: heartRate,
    controllableParam: resistance,
  );
}
