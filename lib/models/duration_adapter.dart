import 'package:hive/hive.dart';

class DurationAdapter extends TypeAdapter<Duration> {
  @override
  final int typeId = 100; // Use a high typeId to avoid conflicts

  @override
  Duration read(BinaryReader reader) {
    final microseconds = reader.readInt();
    return Duration(microseconds: microseconds);
  }

  @override
  void write(BinaryWriter writer, Duration obj) {
    writer.writeInt(obj.inMicroseconds);
  }
}
