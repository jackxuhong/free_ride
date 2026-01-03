import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 7)
class UserProfile extends HiveObject {
  @HiveField(0)
  String name;
  
  @HiveField(1)
  double bodyWeight; // kg

  UserProfile({
    required this.name,
    required this.bodyWeight,
  });
}
