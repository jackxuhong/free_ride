/// Power calculation lookup table for Echelon bikes
/// Based on cadence (RPM) and resistance level (1-32)
class EchelonPowerTable {
  // Power table: 33 resistance levels × 11 cadence ranges
  // Cadence ranges: 0-9, 10-19, 20-29, 30-39, 40-49, 50-59, 60-69, 70-79, 80-89, 90-99, 100+
  static const int resistanceLevels = 33;
  static const int cadenceRanges = 11;
  
  // Default power table from Echelon reference implementation
  static const List<List<double>> defaultTable = [
    [0.0, 1.0, 2.2, 4.8, 9.5, 13.6, 16.7, 22.6, 26.3, 29.2, 47.0],
    [0.0, 1.0, 2.2, 4.8, 9.5, 13.6, 16.7, 22.6, 26.3, 29.2, 47.0],
    [0.0, 1.3, 3.0, 5.4, 10.4, 14.5, 18.5, 24.6, 27.6, 33.5, 49.5],
    [0.0, 1.5, 3.7, 6.0, 11.3, 16.3, 21.3, 28.0, 33.0, 38.0, 54.0],
    [0.0, 1.7, 4.5, 7.2, 12.8, 18.7, 25.2, 32.6, 39.0, 45.2, 61.2],
    [0.0, 2.0, 5.2, 8.8, 14.9, 21.7, 29.2, 37.8, 45.0, 54.0, 71.2],
    [0.0, 2.2, 6.0, 10.4, 17.0, 24.7, 33.1, 43.0, 51.2, 62.7, 81.3],
    [0.0, 2.5, 6.7, 12.0, 19.1, 27.7, 37.1, 48.2, 57.8, 71.5, 91.5],
    [0.0, 2.7, 7.5, 13.6, 21.2, 30.7, 41.0, 53.4, 64.8, 80.3, 101.8],
    [0.0, 3.0, 8.2, 15.2, 23.3, 33.7, 45.0, 58.6, 71.8, 89.0, 108.2],
    [0.0, 3.2, 10.4, 24.0, 36.6, 42.5, 56.3, 74.0, 85.0, 98.2, 123.5],
    [0.0, 3.5, 10.9, 25.1, 38.5, 47.6, 65.4, 83.0, 93.0, 114.8, 136.8],
    [0.0, 3.7, 11.5, 26.0, 41.0, 53.2, 71.6, 90.0, 100.0, 121.7, 149.2],
    [0.0, 4.0, 12.1, 27.5, 43.6, 56.0, 82.3, 101.0, 113.6, 143.0, 162.8],
    [0.0, 4.2, 12.7, 29.7, 46.7, 64.2, 87.9, 109.2, 128.9, 154.0, 172.3],
    [0.0, 4.5, 13.7, 32.0, 50.0, 71.8, 95.6, 113.8, 135.6, 165.0, 185.0],
    [0.0, 4.7, 14.9, 34.5, 54.2, 77.0, 100.7, 127.0, 147.6, 180.0, 200.0],
    [0.0, 5.0, 15.8, 36.5, 58.3, 83.4, 110.1, 136.0, 168.1, 196.0, 213.5],
    [0.0, 5.6, 17.0, 39.5, 64.3, 88.8, 123.4, 154.0, 182.0, 210.0, 235.0],
    [0.0, 6.1, 18.2, 44.0, 70.7, 99.9, 133.3, 166.0, 198.0, 230.0, 253.5],
    [0.0, 6.8, 19.4, 49.0, 79.0, 108.8, 147.2, 185.0, 217.0, 255.2, 278.0],
    [0.0, 7.6, 22.0, 54.8, 88.0, 127.0, 167.0, 212.0, 244.0, 287.0, 305.0],
    [0.0, 8.7, 26.0, 62.0, 100.0, 145.0, 190.0, 242.0, 281.0, 315.1, 350.0],
    [0.0, 9.2, 30.0, 71.0, 114.4, 161.6, 215.1, 275.1, 317.0, 358.5, 390.0],
    [0.0, 9.8, 36.0, 82.5, 134.5, 195.3, 252.5, 313.7, 360.0, 420.3, 460.0],
    [0.0, 10.5, 43.0, 95.0, 157.1, 228.4, 300.1, 374.1, 403.8, 487.8, 540.0],
    [0.0, 12.5, 48.0, 99.3, 162.2, 232.9, 310.4, 400.3, 435.5, 530.5, 589.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
    [0.0, 13.0, 53.0, 102.0, 170.3, 242.0, 320.0, 427.9, 475.2, 570.0, 625.0],
  ];

  /// Calculates power (watts) from cadence (RPM) and resistance level (1-32)
  /// Uses linear interpolation for values between table entries
  static double calculatePower({
    required double cadence,
    required int resistance,
  }) {
    if (cadence == 0) {
      return 0.0;
    }

    // Clamp resistance to valid range (0-32, where 0 is treated as level 0)
    final level = resistance.clamp(0, resistanceLevels - 1);
    
    // Get the power values for this resistance level
    final wattsOfLevel = defaultTable[level];
    
    // Determine cadence range index (each range is 10 RPM)
    final cadenceStep = (cadence / 10.0).floor();
    
    // If cadence is 100+, use the last column with scaling
    if (cadenceStep >= cadenceRanges - 1) {
      return (cadence / 100.0) * wattsOfLevel[cadenceRanges - 1];
    }
    
    // Linear interpolation between cadence ranges
    final wattBase = wattsOfLevel[cadenceStep];
    final wattNext = wattsOfLevel[cadenceStep + 1];
    final cadenceRemainder = cadence % 10;
    
    return wattBase + ((wattNext - wattBase) / 10.0) * cadenceRemainder;
  }
}
