import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/models/user_profile.dart';

class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  static const String _boxName = 'profile';
  static const String _profileKey = 'user_profile';

  Box<UserProfile>? _box;

  Future<void> init() async {
    if (_box != null) return;
    
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    
    _box = await Hive.openBox<UserProfile>(_boxName);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await init();
    await _box!.put(_profileKey, profile);
  }

  Future<UserProfile?> getProfile() async {
    await init();
    return _box!.get(_profileKey);
  }

  Future<bool> hasProfile() async {
    await init();
    return _box!.containsKey(_profileKey);
  }

  Future<void> deleteProfile() async {
    await init();
    await _box!.delete(_profileKey);
  }
}
