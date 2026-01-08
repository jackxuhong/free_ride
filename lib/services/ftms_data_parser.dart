import 'package:free_ride/models/device_data_snapshot.dart';

/// Handles parsing of FTMS data packets into DeviceDataSnapshot
class FTMSDataParser {
  /// Parse Indoor Bike Data (UUID 0x2AD2)
  static DeviceDataSnapshot parseIndoorBikeData(List<int> data) {
    if (data.length < 4) return DeviceDataSnapshot();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    double? cadence;
    double? power;
    int? heartRate;
    double? resistance;

    // Speed (bit 0 always present for instantaneous speed)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01; // Resolution: 0.01 km/h
      offset += 2;
    }

    // Cadence (bit 2)
    if ((flags & 0x04) != 0 && offset + 2 <= data.length) {
      final cadenceRaw = data[offset] | (data[offset + 1] << 8);
      cadence = cadenceRaw * 0.5; // Resolution: 0.5 RPM
      offset += 2;
    }

    // Power (bit 6)
    if ((flags & 0x40) != 0 && offset + 2 <= data.length) {
      final powerRaw = data[offset] | (data[offset + 1] << 8);
      power = powerRaw.toDouble(); // Resolution: 1 W
      offset += 2;
    }

    // Resistance (bit 5)
    if ((flags & 0x20) != 0 && offset + 2 <= data.length) {
      final resistanceRaw = data[offset] | (data[offset + 1] << 8);
      resistance = resistanceRaw.toDouble();
      offset += 2;
    }

    // Heart Rate (bit 9)
    if ((flags & 0x100) != 0 && offset + 1 <= data.length) {
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

  /// Parse Treadmill Data (UUID 0x2ACD)
  static DeviceDataSnapshot parseTreadmillData(List<int> data) {
    if (data.length < 4) return DeviceDataSnapshot();

    final flags = data[0] | (data[1] << 8);
    int offset = 2;

    double? speed;
    double? pace;
    double? incline;
    int? heartRate;

    // Speed (bit 0 always present)
    if (offset + 2 <= data.length) {
      final speedRaw = data[offset] | (data[offset + 1] << 8);
      speed = speedRaw * 0.01; // Resolution: 0.01 km/h
      offset += 2;
    }

    // Pace (bit 5)
    if ((flags & 0x20) != 0 && offset + 1 <= data.length) {
      pace = data[offset].toDouble(); // min/km
      offset += 1;
    }

    // Incline (bit 3)
    if ((flags & 0x08) != 0 && offset + 2 <= data.length) {
      final inclineRaw = data[offset] | (data[offset + 1] << 8);
      incline = inclineRaw * 0.1; // Resolution: 0.1%
      offset += 2;
    }

    // Heart Rate (bit 8)
    if ((flags & 0x100) != 0 && offset + 1 <= data.length) {
      heartRate = data[offset];
      offset += 1;
    }

    return DeviceDataSnapshot(
      speed: speed,
      cadenceOrPace: pace,
      controllableParam: incline,
      heartRate: heartRate,
    );
  }
}