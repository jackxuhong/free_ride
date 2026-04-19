import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/services/heart_rate_monitor_service.dart';

void main() {
  group('HeartRateMonitorService.parseHeartRate', () {
    test('returns 0 for empty data', () {
      expect(HeartRateMonitorService.parseHeartRate([]), 0);
    });

    test('returns 0 for flags-only data (too short for UINT8)', () {
      expect(HeartRateMonitorService.parseHeartRate([0x00]), 0);
    });

    test('parses UINT8 heart rate (flags bit 0 = 0)', () {
      // flags = 0x00 (UINT8 format), HR = 72
      expect(HeartRateMonitorService.parseHeartRate([0x00, 72]), 72);
    });

    test('parses UINT8 heart rate at resting value', () {
      expect(HeartRateMonitorService.parseHeartRate([0x00, 60]), 60);
    });

    test('parses UINT8 heart rate at max exertion', () {
      expect(HeartRateMonitorService.parseHeartRate([0x00, 200]), 200);
    });

    test('parses UINT8 heart rate of 255 (max UINT8)', () {
      expect(HeartRateMonitorService.parseHeartRate([0x00, 255]), 255);
    });

    test('parses UINT16 heart rate (flags bit 0 = 1)', () {
      // flags = 0x01 (UINT16 format), HR = 72 (little-endian: 0x48, 0x00)
      expect(HeartRateMonitorService.parseHeartRate([0x01, 0x48, 0x00]), 72);
    });

    test('parses UINT16 heart rate > 255', () {
      // flags = 0x01, HR = 300 (little-endian: 0x2C, 0x01)
      expect(HeartRateMonitorService.parseHeartRate([0x01, 0x2C, 0x01]), 300);
    });

    test('returns 0 for UINT16 with insufficient data', () {
      // flags = 0x01 (UINT16) but only 2 bytes total
      expect(HeartRateMonitorService.parseHeartRate([0x01, 0x48]), 0);
    });

    test('parses UINT8 with extra flags set (contact, energy, RR)', () {
      // flags = 0x1E: bit0=0 (UINT8), bit1-2=contact supported/detected,
      // bit3=energy present, bit4=RR present
      // HR = 145, followed by additional data bytes
      expect(
        HeartRateMonitorService.parseHeartRate(
          [0x1E, 145, 0x00, 0x00, 0x00, 0x00],
        ),
        145,
      );
    });

    test('parses UINT16 with extra flags set', () {
      // flags = 0x1F: bit0=1 (UINT16), other flags set
      // HR = 500 (little-endian: 0xF4, 0x01)
      expect(
        HeartRateMonitorService.parseHeartRate(
          [0x1F, 0xF4, 0x01, 0x00, 0x00, 0x00],
        ),
        500,
      );
    });

    test('parses UINT8 heart rate of 0', () {
      expect(HeartRateMonitorService.parseHeartRate([0x00, 0]), 0);
    });

    test('parses UINT16 heart rate of 0', () {
      expect(HeartRateMonitorService.parseHeartRate([0x01, 0x00, 0x00]), 0);
    });

    test('ignores flags beyond bit 0 for HR value extraction', () {
      // flags = 0xFE: bit0=0 (UINT8), all other bits set
      // HR = 88
      expect(HeartRateMonitorService.parseHeartRate([0xFE, 88]), 88);
    });
  });
}
