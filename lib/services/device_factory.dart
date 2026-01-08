import 'package:free_ride/models/fitness_device.dart';
import 'package:free_ride/services/echelon_service.dart';
import 'package:free_ride/services/ftms_service.dart';
import 'package:free_ride/services/virtual_device_interface.dart';
import 'package:free_ride/services/virtual_indoor_bike.dart';
import 'package:free_ride/services/virtual_treadmill.dart';

/// Protocol types for device communication
enum DeviceProtocol {
  ftmsBluetooth,
  echelonBluetooth,
  virtual,
  // Future: wifi, antPlus, etc.
}

/// Abstract factory for creating fitness devices
abstract class DeviceFactory {
  VirtualFitnessDevice createDevice(FitnessDevice config);
  DeviceProtocol get protocol;
}

/// Factory for FTMS Bluetooth devices
class FTMSDeviceFactory implements DeviceFactory {
  @override
  DeviceProtocol get protocol => DeviceProtocol.ftmsBluetooth;

  @override
  VirtualFitnessDevice createDevice(FitnessDevice config) {
    return FTMSService(device: config);
  }
}

/// Factory for Echelon Bluetooth devices
class EchelonDeviceFactory implements DeviceFactory {
  @override
  DeviceProtocol get protocol => DeviceProtocol.echelonBluetooth;

  @override
  VirtualFitnessDevice createDevice(FitnessDevice config) {
    return EchelonService(device: config);
  }
}

/// Factory for virtual devices
class VirtualDeviceFactory implements DeviceFactory {
  @override
  DeviceProtocol get protocol => DeviceProtocol.virtual;

  @override
  VirtualFitnessDevice createDevice(FitnessDevice config) {
    if (config.deviceType == DeviceType.indoorBike) {
      return VirtualIndoorBike(targetSpeed: config.effortLevel);
    } else {
      return VirtualTreadmill(userSpeed: config.effortLevel);
    }
  }
}

/// Registry for managing device factories
class DeviceFactoryRegistry {
  final Map<DeviceProtocol, DeviceFactory> _factories = {};

  DeviceFactoryRegistry() {
    // Register default factories
    registerFactory(DeviceProtocol.ftmsBluetooth, FTMSDeviceFactory());
    registerFactory(DeviceProtocol.echelonBluetooth, EchelonDeviceFactory());
    registerFactory(DeviceProtocol.virtual, VirtualDeviceFactory());
  }

  void registerFactory(DeviceProtocol protocol, DeviceFactory factory) {
    _factories[protocol] = factory;
  }

  VirtualFitnessDevice createDevice(FitnessDevice config) {
    // For now, determine protocol from device properties
    // In future, config will have explicit protocol field
    DeviceProtocol protocol;
    if (config.isVirtual) {
      protocol = DeviceProtocol.virtual;
    } else if (config.name.toLowerCase().contains('echelon')) {
      protocol = DeviceProtocol.echelonBluetooth;
    } else {
      protocol = DeviceProtocol.ftmsBluetooth;
    }

    final factory = _factories[protocol];
    if (factory == null) {
      throw UnsupportedError('No factory registered for protocol: $protocol');
    }
    return factory.createDevice(config);
  }
}