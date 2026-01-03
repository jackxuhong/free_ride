import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 7)
class UserProfile extends HiveObject {
  @HiveField(0)
  String name;
  
  @HiveField(1)
  double bodyWeight; // kg
  
  @HiveField(2, defaultValue: '')
  String email;

  UserProfile({
    required this.name,
    required this.bodyWeight,
    this.email = '',
  });
}
