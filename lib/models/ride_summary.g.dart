// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ride_summary.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RideSummaryAdapter extends TypeAdapter<RideSummary> {
  @override
  final int typeId = 6;

  @override
  RideSummary read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RideSummary(
      totalDuration: fields[0] as Duration,
      movingTime: fields[1] as Duration,
      pausedTime: fields[2] as Duration,
      startTime: fields[3] as DateTime,
      endTime: fields[4] as DateTime?,
      totalDistance: fields[5] as double,
      completedDistance: fields[6] as double,
      completionPercentage: fields[7] as double,
      averageSpeed: fields[8] as double,
      averageMovingSpeed: fields[9] as double,
      maxSpeed: fields[10] as double,
      minSpeed: fields[11] as double,
      totalElevationGain: fields[12] as double,
      totalElevationLoss: fields[13] as double,
      maxGrade: fields[14] as double,
      minGrade: fields[15] as double,
      currentElevation: fields[16] as double,
      caloriesBurned: fields[17] as int,
      averagePower: fields[18] as double,
      routeId: fields[19] as String,
      routeName: fields[20] as String,
      completed: fields[21] as bool,
      cancellationReason: fields[22] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, RideSummary obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.totalDuration)
      ..writeByte(1)
      ..write(obj.movingTime)
      ..writeByte(2)
      ..write(obj.pausedTime)
      ..writeByte(3)
      ..write(obj.startTime)
      ..writeByte(4)
      ..write(obj.endTime)
      ..writeByte(5)
      ..write(obj.totalDistance)
      ..writeByte(6)
      ..write(obj.completedDistance)
      ..writeByte(7)
      ..write(obj.completionPercentage)
      ..writeByte(8)
      ..write(obj.averageSpeed)
      ..writeByte(9)
      ..write(obj.averageMovingSpeed)
      ..writeByte(10)
      ..write(obj.maxSpeed)
      ..writeByte(11)
      ..write(obj.minSpeed)
      ..writeByte(12)
      ..write(obj.totalElevationGain)
      ..writeByte(13)
      ..write(obj.totalElevationLoss)
      ..writeByte(14)
      ..write(obj.maxGrade)
      ..writeByte(15)
      ..write(obj.minGrade)
      ..writeByte(16)
      ..write(obj.currentElevation)
      ..writeByte(17)
      ..write(obj.caloriesBurned)
      ..writeByte(18)
      ..write(obj.averagePower)
      ..writeByte(19)
      ..write(obj.routeId)
      ..writeByte(20)
      ..write(obj.routeName)
      ..writeByte(21)
      ..write(obj.completed)
      ..writeByte(22)
      ..write(obj.cancellationReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RideSummaryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
