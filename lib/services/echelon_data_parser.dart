import 'dart:typed_data';
import 'package:free_ride/models/device_data_snapshot.dart';

/// Parses data packets from Echelon Connect Sport devices
class EchelonDataParser {
  /// Parse raw data packet from Echelon device
  static DeviceDataSnapshot parseData(List<int> rawData) {
    if (rawData.isEmpty) {
      return DeviceDataSnapshot();
    }

    final data = Uint8List.fromList(rawData);

    // Echelon Connect Sport data packet structure (based on C++ implementation)
    // Packet format appears to be: [header, data1, data2, ..., checksum]

    if (data.length < 8) {
      return DeviceDataSnapshot();
    }

    try {
      // Parse speed (km/h) - typically at positions 5-6
      final speedRaw = (data[5] << 8) | data[6];
      final speed = speedRaw / 100.0; // Convert to km/h

      // Parse cadence (rpm) - typically at positions 7-8
      final cadenceRaw = (data[7] << 8) | data[8];
      final cadence = cadenceRaw / 10.0; // Convert to rpm

      // Parse power (watts) - calculated from resistance and cadence
      // Echelon provides resistance level, power needs to be calculated
      final resistance = data[3]; // Resistance level
      final power = _calculatePowerFromResistance(resistance, cadence);

      return DeviceDataSnapshot(
        speed: speed,
        cadenceOrPace: cadence,
        power: power,
        controllableParam: resistance.toDouble(),
      );
    } catch (e) {
      // Return default snapshot if parsing fails
      return DeviceDataSnapshot();
    }
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