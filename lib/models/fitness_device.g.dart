// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fitness_device.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FitnessDeviceAdapter extends TypeAdapter<FitnessDevice> {
  @override
  final int typeId = 8;

  @override
  FitnessDevice read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FitnessDevice(
      id: fields[0] as String,
      name: fields[1] as String,
      deviceType: fields[2] as DeviceType,
      isVirtual: fields[3] as bool,
      deviceAddress: fields[4] as String?,
      lastConnected: fields[5] as DateTime?,
      effortLevel: fields[6] as double,
      controllableParam: fields[7] as double,
    );
  }

  @override
  void write(BinaryWriter writer, FitnessDevice obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.deviceType)
      ..writeByte(3)
      ..write(obj.isVirtual)
      ..writeByte(4)
      ..write(obj.deviceAddress)
      ..writeByte(5)
      ..write(obj.lastConnected)
      ..writeByte(6)
      ..write(obj.effortLevel)
      ..writeByte(7)
      ..write(obj.controllableParam);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FitnessDeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DeviceTypeAdapter extends TypeAdapter<DeviceType> {
  @override
  final int typeId = 9;

  @override
  DeviceType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DeviceType.indoorBike;
      case 1:
        return DeviceType.treadmill;
      default:
        return DeviceType.indoorBike;
    }
  }

  @override
  void write(BinaryWriter writer, DeviceType obj) {
    switch (obj) {
      case DeviceType.indoorBike:
        writer.writeByte(0);
        break;
      case DeviceType.treadmill:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
