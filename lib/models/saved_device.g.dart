// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_device.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedDeviceAdapter extends TypeAdapter<SavedDevice> {
  @override
  final int typeId = 10;

  @override
  SavedDevice read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedDevice(
      id: fields[0] as String,
      bluetoothName: fields[1] as String,
      customName: fields[2] as String,
      address: fields[3] as String,
      adapterType: fields[4] as String,
      deviceTypeString: fields[5] as String,
      powerCalibration: fields[6] as double,
      lastConnected: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, SavedDevice obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.bluetoothName)
      ..writeByte(2)
      ..write(obj.customName)
      ..writeByte(3)
      ..write(obj.address)
      ..writeByte(4)
      ..write(obj.adapterType)
      ..writeByte(5)
      ..write(obj.deviceTypeString)
      ..writeByte(6)
      ..write(obj.powerCalibration)
      ..writeByte(7)
      ..write(obj.lastConnected);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedDeviceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
