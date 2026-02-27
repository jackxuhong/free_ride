import 'dart:math';

class RideCalculator {
  /// Calculate average speed
  static double calculateAverageSpeed(double distanceMeters, Duration duration) {
    if (duration.inSeconds == 0) return 0;
    final distanceKm = distanceMeters / 1000.0;
    final hours = duration.inSeconds / 3600.0;
    return distanceKm / hours;
  }

  /// Calculate speed adjusted for grade
  static double calculateAdjustedSpeed({
    required double baseSpeed,
    required double grade,
    required double speedMultiplier,
    required double gradeAdjustmentFactor,
  }) {
    // grade is in decimal form (0.10 = 10%)
    // Adjust speed: uphill reduces speed, downhill increases speed
    final adjustment = 1.0 - (grade * gradeAdjustmentFactor);
    return baseSpeed * speedMultiplier * adjustment;
  }

  /// Calculate grade (slope) between two elevations
  static double calculateGrade(
    double elevation1,
    double elevation2,
    double distance,
  ) {
    if (distance == 0) return 0;
    final elevationChange = elevation2 - elevation1;
    return elevationChange / distance; // Returns decimal (0.10 = 10%)
  }

  /// Calculate all grades for a route
  static List<double> calculateGrades(
    List<double> elevations,
    List<double> segmentDistances,
  ) {
    final grades = <double>[];

    for (int i = 0; i < elevations.length - 1; i++) {
      final grade = calculateGrade(
        elevations[i],
        elevations[i + 1],
        segmentDistances[i],
      );
      grades.add(grade);
    }

    return grades;
  }

  /// Calculate total elevation gain and loss
  static ElevationChange calculateElevationChange(List<double> elevations) {
    double gain = 0;
    double loss = 0;

    for (int i = 0; i < elevations.length - 1; i++) {
      final change = elevations[i + 1] - elevations[i];
      if (change > 0) {
        gain += change;
      } else {
        loss += change.abs();
      }
    }

    return ElevationChange(gain: gain, loss: loss);
  }

  /// Estimate calories burned using MET (Metabolic Equivalent)
  static int estimateCalories({
    required double distanceMeters,
    required double elevationGainMeters,
    required Duration duration,
    double riderWeightKg = 70.0, // matches AppConstants.defaultBodyWeightKg
  }) {
    final avgSpeed = calculateAverageSpeed(distanceMeters, duration);

    // Base MET value for cycling based on speed
    double met;
    if (avgSpeed < 16) {
      met = 8.0; // Light effort
    } else if (avgSpeed < 25) {
      met = 10.0; // Moderate effort
    } else {
      met = 12.0; // Vigorous effort
    }

    // Add MET for climbing (approximately 0.5 MET per 100m of elevation gain)
    met += (elevationGainMeters / 100) * 0.5;

    // Calories = MET * weight(kg) * time(hours)
    final hours = duration.inSeconds / 3600.0;
    final calories = met * riderWeightKg * hours;

    return calories.round();
  }

  /// Estimate power output in watts
  static double estimatePower({
    required double speedKmh,
    required double grade,
    double riderWeightKg = 70.0, // matches AppConstants.defaultBodyWeightKg
    double bikeWeightKg = 10.0,
  }) {
    final totalWeight = riderWeightKg + bikeWeightKg;
    final speedMs = speedKmh / 3.6; // Convert to m/s

    // Gravitational power (climbing/descending)
    final gravitationalPower = totalWeight * 9.81 * speedMs * grade;

    // Air resistance power
    // P = 0.5 * rho * Cd * A * v^3
    // rho = air density (1.225 kg/m^3), Cd = drag coefficient (0.3),
    // A = frontal area (0.5 m^2)
    final airResistancePower = 0.5 * 1.225 * 0.3 * 0.5 * pow(speedMs, 3);

    // Rolling resistance power
    // P = Crr * m * g * v
    // Crr = rolling resistance coefficient (0.004)
    final rollingResistancePower = 0.004 * totalWeight * 9.81 * speedMs;

    final totalPower =
        gravitationalPower + airResistancePower + rollingResistancePower;

    return max(0, totalPower); // Power cannot be negative
  }

  /// Calculate average power over a ride
  static double calculateAveragePower(List<PowerSample> powerSamples) {
    if (powerSamples.isEmpty) return 0;
    final sum = powerSamples.fold<double>(0, (sum, sample) => sum + sample.power);
    return sum / powerSamples.length;
  }
}

class ElevationChange {
  final double gain;
  final double loss;

  ElevationChange({required this.gain, required this.loss});
}

class PowerSample {
  final double power;
  final DateTime timestamp;

  PowerSample({required this.power, required this.timestamp});
}
