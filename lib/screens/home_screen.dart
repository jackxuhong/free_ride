import 'package:flutter/material.dart';
import 'package:free_ride/screens/input_screen.dart';
import 'package:free_ride/screens/history_screen.dart';
import 'package:free_ride/screens/device_setup_screen.dart';
import 'package:free_ride/screens/profile_screen.dart';
import 'package:free_ride/services/profile_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _profileService = ProfileService();
  bool _isLoading = true;
  final GlobalKey<HistoryScreenRefreshState> _historyKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final hasProfile = await _profileService.hasProfile();
    if (mounted) {
      setState(() {
        _currentIndex = hasProfile ? 0 : 3; // Routes if has profile, Profile if not
        _isLoading = false;
      });
    }
  }

  void _onProfileSaved() {
    setState(() {
      _currentIndex = 0; // Navigate to Routes tab
    });
  }

  List<Widget> get _screens => [
        const InputScreen(),
        HistoryScreenRefresh(key: _historyKey),
        const DeviceSetupScreen(),
        ProfileScreen(onProfileSaved: _onProfileSaved),
      ];

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          // Refresh history when tapping the History tab
          if (index == 1) {
            _historyKey.currentState?.refresh();
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.route),
            label: 'Routes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Devices',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
