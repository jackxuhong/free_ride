import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';

/// Parses data packets from Echelon Connect Sport devices
class EchelonDataParser {
  static int _lastResistance = 1; // Track last known resistance level

  /// Parse raw data packet from Echelon device
  static DeviceDataSnapshot parseData(List<int> rawData) {
    if (rawData.isEmpty) {
      return DeviceDataSnapshot();
    }

    final data = Uint8List.fromList(rawData);

    // Handle different packet types based on C++ implementation
    if (data.length == 5 && data[0] == 0xf0 && data[1] == 0xd2) {
      // Resistance update packet: [0xf0, 0xd2, ?, resistance, ?]
      final resistance = data[3];
      _lastResistance = resistance;
      return DeviceDataSnapshot(
        controllableParam: resistance.toDouble(),
      );
    }

    if (data.length == 13) {
      // Main data packet (13 bytes)
      try {
        // Cadence (rpm) - byte 10
        final cadence = data[10].toDouble();

        // Speed calculation: 0.37497622 * cadence (from C++ code)
        final speed = 0.37497622 * cadence;

        // Power calculation from resistance and cadence
        final power = _calculatePowerFromResistance(_lastResistance, cadence);

        return DeviceDataSnapshot(
          speed: speed,
          cadenceOrPace: cadence,
          power: power,
          controllableParam: _lastResistance.toDouble(),
        );
      } catch (e) {
        print('Error parsing Echelon data packet: $e');
        return DeviceDataSnapshot();
      }
    }

    // Unknown packet format
    return DeviceDataSnapshot();
  }

  /// Calculate power from resistance level and cadence
  /// Based on Echelon's power curves from the C++ implementation
  static double _calculatePowerFromResistance(int resistance, double cadence) {
    if (cadence <= 0) return 0;

    // Simplified power calculation based on Echelon's watt tables
    // This is an approximation - real implementation would use the full tables
    const double basePower = 25.0; // Base power at level 1, 60 rpm
    const double powerPerLevel = 15.0; // Additional power per resistance level
    final double cadenceFactor = cadence / 60.0; // Normalize to 60 rpm baseline

    return (basePower + (resistance - 1) * powerPerLevel) * cadenceFactor;
  }
}