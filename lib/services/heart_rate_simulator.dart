import 'dart:math';

/// Simulates realistic heart rate dynamics
class HeartRateSimulator {
  double _currentHR;
  final double restingHR;
  final double maxHR;
  final Random _random = Random();

  HeartRateSimulator({
    double? currentHR,
    this.restingHR = 70.0,
    this.maxHR = 190.0,
  }) : _currentHR = currentHR ?? restingHR;

  /// Get current heart rate
  double get currentHR => _currentHR;

  /// Update heart rate based on effort level and intensity
  /// Returns the new heart rate in bpm
  double updateHeartRate({
    required double effortLevel, // 0-100%
    required double deltaTime, // seconds
    required double intensityMultiplier, // 0.5-2.0
  }) {
    // Calculate target HR based on effort and intensity
    // Intensity affects how hard the effort feels physiologically
    final intensityEffect = sqrt(intensityMultiplier);
    final targetHR = restingHR + (maxHR - restingHR) * (effortLevel / 100.0) * intensityEffect;

    // HR increases faster than it decreases (recovery is slower)
    final responseRate = targetHR > _currentHR ? 0.15 : 0.05;

    // Exponential approach to target
    final delta = (targetHR - _currentHR) * responseRate * deltaTime;
    _currentHR += delta;

    // Clamp to valid range
    _currentHR = _currentHR.clamp(restingHR, maxHR);

    // Add random variability (±2 bpm) for realism
    final variability = (_random.nextDouble() - 0.5) * 4.0;
    _currentHR += variability;
    _currentHR = _currentHR.clamp(restingHR, maxHR);

    return _currentHR;
  }

  /// Reset to resting heart rate
  void reset() {
    _currentHR = restingHR;
  }

  /// Get HR zone (1-5)
  int getHRZone() {
    final percentage = (_currentHR - restingHR) / (maxHR - restingHR);
    if (percentage < 0.6) return 1; // Recovery
    if (percentage < 0.7) return 2; // Endurance
    if (percentage < 0.8) return 3; // Tempo
    if (percentage < 0.9) return 4; // Threshold
    return 5; // VO2 Max
  }

  /// Get HR zone name
  String getHRZoneName() {
    switch (getHRZone()) {
      case 1:
        return 'Recovery';
      case 2:
        return 'Endurance';
      case 3:
        return 'Tempo';
      case 4:
        return 'Threshold';
      case 5:
        return 'VO2 Max';
      default:
        return 'Unknown';
    }
  }
}
