// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_route.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedRouteAdapter extends TypeAdapter<SavedRoute> {
  @override
  final int typeId = 0;

  @override
  SavedRoute read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedRoute(
      id: fields[0] as String,
      timestamp: fields[1] as DateTime,
      startInput: fields[2] as String,
      endInput: fields[3] as String,
      coordinates: fields[4] as RouteCoordinates,
      geometry: fields[5] as RouteGeometry,
      elevationProfile: fields[6] as ElevationProfile,
      customName: fields[7] as String?,
      waypointInputs: (fields[8] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, SavedRoute obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.startInput)
      ..writeByte(3)
      ..write(obj.endInput)
      ..writeByte(4)
      ..write(obj.coordinates)
      ..writeByte(5)
      ..write(obj.geometry)
      ..writeByte(6)
      ..write(obj.elevationProfile)
      ..writeByte(7)
      ..write(obj.customName)
      ..writeByte(8)
      ..write(obj.waypointInputs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedRouteAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RouteCoordinatesAdapter extends TypeAdapter<RouteCoordinates> {
  @override
  final int typeId = 1;

  @override
  RouteCoordinates read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RouteCoordinates(
      startLat: fields[0] as double,
      startLon: fields[1] as double,
      endLat: fields[2] as double,
      endLon: fields[3] as double,
      waypoints: (fields[4] as List).cast<LatLngPoint>(),
    );
  }

  @override
  void write(BinaryWriter writer, RouteCoordinates obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.startLat)
      ..writeByte(1)
      ..write(obj.startLon)
      ..writeByte(2)
      ..write(obj.endLat)
      ..writeByte(3)
      ..write(obj.endLon)
      ..writeByte(4)
      ..write(obj.waypoints);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteCoordinatesAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LatLngPointAdapter extends TypeAdapter<LatLngPoint> {
  @override
  final int typeId = 2;

  @override
  LatLngPoint read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LatLngPoint(
      fields[0] as double,
      fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, LatLngPoint obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.latitude)
      ..writeByte(1)
      ..write(obj.longitude);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLngPointAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RouteGeometryAdapter extends TypeAdapter<RouteGeometry> {
  @override
  final int typeId = 3;

  @override
  RouteGeometry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RouteGeometry(
      totalDistance: fields[0] as double,
      segmentDistances: (fields[1] as List).cast<double>(),
    );
  }

  @override
  void write(BinaryWriter writer, RouteGeometry obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.totalDistance)
      ..writeByte(1)
      ..write(obj.segmentDistances);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteGeometryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ElevationProfileAdapter extends TypeAdapter<ElevationProfile> {
  @override
  final int typeId = 4;

  @override
  ElevationProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ElevationProfile(
      elevations: (fields[0] as List).cast<double>(),
      grades: (fields[1] as List).cast<double>(),
      totalElevationGain: fields[2] as double,
      totalElevationLoss: fields[3] as double,
      maxElevation: fields[4] as double,
      minElevation: fields[5] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ElevationProfile obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.elevations)
      ..writeByte(1)
      ..write(obj.grades)
      ..writeByte(2)
      ..write(obj.totalElevationGain)
      ..writeByte(3)
      ..write(obj.totalElevationLoss)
      ..writeByte(4)
      ..write(obj.maxElevation)
      ..writeByte(5)
      ..write(obj.minElevation);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ElevationProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
