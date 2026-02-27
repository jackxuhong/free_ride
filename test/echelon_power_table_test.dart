import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/services/echelon_power_table.dart';

void main() {
  group('EchelonPowerTable', () {
    test('returns 0 watts at zero cadence', () {
      expect(
        EchelonPowerTable.calculatePower(cadence: 0, resistance: 10),
        0,
      );
    });

    test('returns 0 watts at zero resistance zero cadence', () {
      expect(
        EchelonPowerTable.calculatePower(cadence: 0, resistance: 0),
        0,
      );
    });

    test('returns positive watts for non-zero cadence', () {
      final power = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 10,
      );
      expect(power, greaterThan(0));
    });

    test('higher resistance produces more power at same cadence', () {
      final lowRes = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 5,
      );
      final highRes = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 20,
      );
      expect(highRes, greaterThan(lowRes));
    });

    test('higher cadence produces more power at same resistance', () {
      final lowCadence = EchelonPowerTable.calculatePower(
        cadence: 40,
        resistance: 10,
      );
      final highCadence = EchelonPowerTable.calculatePower(
        cadence: 80,
        resistance: 10,
      );
      expect(highCadence, greaterThan(lowCadence));
    });

    test('clamps resistance below 0 to 0', () {
      // Should not throw
      final power = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: -5,
      );
      expect(power, greaterThanOrEqualTo(0));
    });

    test('clamps resistance above 32 to 32', () {
      final atMax = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 32,
      );
      final aboveMax = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 50,
      );
      expect(aboveMax, atMax);
    });

    test('handles cadence above 100 RPM', () {
      final power = EchelonPowerTable.calculatePower(
        cadence: 120,
        resistance: 15,
      );
      // Should scale the 100+ column value
      expect(power, greaterThan(0));
    });

    test('interpolates between cadence ranges', () {
      final at60 = EchelonPowerTable.calculatePower(
        cadence: 60,
        resistance: 10,
      );
      final at70 = EchelonPowerTable.calculatePower(
        cadence: 70,
        resistance: 10,
      );
      final at65 = EchelonPowerTable.calculatePower(
        cadence: 65,
        resistance: 10,
      );
      // The midpoint should be between the two endpoints
      expect(at65, greaterThanOrEqualTo(at60));
      expect(at65, lessThanOrEqualTo(at70));
    });
  });
}
