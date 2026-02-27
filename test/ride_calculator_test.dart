import 'package:flutter_test/flutter_test.dart';
import 'package:free_ride/services/ride_calculator.dart';

void main() {
  group('RideCalculator', () {
    group('calculateAverageSpeed', () {
      test('returns 0 when duration is zero', () {
        expect(RideCalculator.calculateAverageSpeed(1000, Duration.zero), 0);
      });

      test('calculates correct speed for 1 km in 1 hour', () {
        final speed = RideCalculator.calculateAverageSpeed(
          1000,
          const Duration(hours: 1),
        );
        expect(speed, closeTo(1.0, 0.01)); // 1 km/h
      });

      test('calculates correct speed for 10 km in 30 minutes', () {
        final speed = RideCalculator.calculateAverageSpeed(
          10000,
          const Duration(minutes: 30),
        );
        expect(speed, closeTo(20.0, 0.01)); // 20 km/h
      });
    });

    group('calculateAdjustedSpeed', () {
      test('returns base × multiplier on flat terrain', () {
        final speed = RideCalculator.calculateAdjustedSpeed(
          baseSpeed: 20.0,
          grade: 0.0,
          speedMultiplier: 1.0,
          gradeAdjustmentFactor: 0.1,
        );
        expect(speed, closeTo(20.0, 0.01));
      });

      test('reduces speed uphill', () {
        final speed = RideCalculator.calculateAdjustedSpeed(
          baseSpeed: 20.0,
          grade: 0.10, // 10% grade
          speedMultiplier: 1.0,
          gradeAdjustmentFactor: 0.1,
        );
        expect(speed, lessThan(20.0));
        // adjustment = 1.0 - (0.10 * 0.1) = 0.99
        expect(speed, closeTo(19.8, 0.01));
      });

      test('increases speed downhill', () {
        final speed = RideCalculator.calculateAdjustedSpeed(
          baseSpeed: 20.0,
          grade: -0.10, // -10% grade
          speedMultiplier: 1.0,
          gradeAdjustmentFactor: 0.1,
        );
        expect(speed, greaterThan(20.0));
      });

      test('applies speed multiplier', () {
        final speed = RideCalculator.calculateAdjustedSpeed(
          baseSpeed: 20.0,
          grade: 0.0,
          speedMultiplier: 10.0,
          gradeAdjustmentFactor: 0.1,
        );
        expect(speed, closeTo(200.0, 0.01));
      });
    });

    group('calculateGrade', () {
      test('returns 0 when distance is zero', () {
        expect(RideCalculator.calculateGrade(100, 200, 0), 0);
      });

      test('calculates positive grade correctly', () {
        // 10m rise over 100m distance = 10% grade = 0.10
        final grade = RideCalculator.calculateGrade(100, 110, 100);
        expect(grade, closeTo(0.10, 0.001));
      });

      test('calculates negative grade correctly', () {
        final grade = RideCalculator.calculateGrade(110, 100, 100);
        expect(grade, closeTo(-0.10, 0.001));
      });
    });

    group('calculateElevationChange', () {
      test('returns zero for single elevation', () {
        final change = RideCalculator.calculateElevationChange([100]);
        expect(change.gain, 0);
        expect(change.loss, 0);
      });

      test('tracks gain correctly', () {
        final change = RideCalculator.calculateElevationChange(
          [100, 150, 200],
        );
        expect(change.gain, closeTo(100, 0.01));
        expect(change.loss, closeTo(0, 0.01));
      });

      test('tracks gain and loss correctly', () {
        final change = RideCalculator.calculateElevationChange(
          [100, 200, 150],
        );
        expect(change.gain, closeTo(100, 0.01));
        expect(change.loss, closeTo(50, 0.01));
      });
    });

    group('estimatePower', () {
      test('returns 0 for zero speed', () {
        final power = RideCalculator.estimatePower(
          speedKmh: 0,
          grade: 0,
        );
        expect(power, 0);
      });

      test('returns positive power for flat terrain', () {
        final power = RideCalculator.estimatePower(
          speedKmh: 20.0,
          grade: 0,
        );
        expect(power, greaterThan(0));
      });

      test('uphill requires more power than flat', () {
        final flatPower = RideCalculator.estimatePower(
          speedKmh: 20.0,
          grade: 0,
        );
        final uphillPower = RideCalculator.estimatePower(
          speedKmh: 20.0,
          grade: 0.05, // 5% grade
        );
        expect(uphillPower, greaterThan(flatPower));
      });
    });

    group('estimateCalories', () {
      test('returns 0 for zero duration', () {
        final calories = RideCalculator.estimateCalories(
          distanceMeters: 1000,
          elevationGainMeters: 0,
          duration: Duration.zero,
        );
        expect(calories, 0);
      });

      test('returns positive calories for a real ride', () {
        final calories = RideCalculator.estimateCalories(
          distanceMeters: 10000,
          elevationGainMeters: 100,
          duration: const Duration(minutes: 30),
        );
        expect(calories, greaterThan(0));
      });
    });

    group('calculateAveragePower', () {
      test('returns 0 for empty samples', () {
        expect(RideCalculator.calculateAveragePower([]), 0);
      });

      test('averages samples correctly', () {
        final samples = [
          PowerSample(power: 100, timestamp: DateTime.now()),
          PowerSample(power: 200, timestamp: DateTime.now()),
          PowerSample(power: 300, timestamp: DateTime.now()),
        ];
        expect(RideCalculator.calculateAveragePower(samples), closeTo(200, 0.01));
      });
    });
  });
}
