import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:free_ride/services/virtual_device_interface.dart';

/// Sends control commands to Echelon Connect Sport devices
class EchelonCommandSender {
  final BluetoothCharacteristic? controlCharacteristic;
  final int minResistance;
  final int maxResistance;

  EchelonCommandSender({
    required this.controlCharacteristic,
    required this.minResistance,
    required this.maxResistance,
  });

  /// Send a control command to the device
  Future<bool> sendControlCommand(ControlCommand command) async {
    if (controlCharacteristic == null) {
      return false;
    }

    try {
      Uint8List commandData;

      if (command is SetResistance) {
        commandData = _createResistanceCommand(command.level);
      } else {
        // Echelon Connect Sport is primarily a bike, doesn't support incline
        return false;
      }

      await controlCharacteristic!.write(commandData);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Create resistance control command
  /// Based on C++ implementation: [0xf0, 0xb1, 0x01, resistance, checksum]
  Uint8List _createResistanceCommand(int resistance) {
    // Clamp resistance to valid range
    final clampedResistance = resistance.clamp(minResistance, maxResistance);

    // Command format: [0xf0, 0xb1, 0x01, resistance, checksum]
    final command = Uint8List(5);
    command[0] = 0xf0; // Header
    command[1] = 0xb1; // Resistance command
    command[2] = 0x01; // Subcommand
    command[3] = clampedResistance; // Resistance level

    // Calculate checksum (sum of first 4 bytes)
    command[4] = (command[0] + command[1] + command[2] + command[3]) & 0xFF;

    return command;
  }

  /// Create poll command to request data
  /// Based on C++ implementation: [0xf0, 0xa0, 0x01, counter, checksum]
  Uint8List createPollCommand(int counter) {
    final command = Uint8List(5);
    command[0] = 0xf0; // Header
    command[1] = 0xa0; // Poll command
    command[2] = 0x01; // Subcommand
    command[3] = counter & 0xFF; // Counter (rolls over)

    // Calculate checksum
    command[4] = (command[0] + command[1] + command[2] + command[3]) & 0xFF;

    return command;
  }
}