import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:free_ride/services/route_storage_service.dart';
import 'package:free_ride/services/profile_service.dart';
import 'package:free_ride/services/device_storage_service.dart';
import 'package:free_ride/providers/route_provider.dart';
import 'package:free_ride/providers/ride_provider.dart';
import 'package:free_ride/providers/device_provider.dart';
import 'package:free_ride/screens/home_screen.dart';
import 'package:free_ride/utils/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load();
  
  // Initialize flutter_blue_plus (removed setLogLevel to avoid conflicts)
  // FlutterBluePlus.setLogLevel(LogLevel.error);

  // Initialize storage
  await RouteStorageService().init();
  await ProfileService().init();
  
  // Initialize device storage
  final settingsBox = await Hive.openBox(AppConstants.settingsBoxName);
  await DeviceStorageService().init(settingsBox);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RouteProvider()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(
          create: (_) => DeviceProvider()..init(),
        ),
      ],
      child: MaterialApp(
        title: 'Free Ride',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
