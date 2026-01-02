# Free Ride - Implementation Complete! 🚴‍♂️

A Flutter bike ride simulation app with physics-based speed calculations based on terrain elevation.

## ✅ Implementation Status

All core features have been implemented:

- ✅ Dependencies configured
- ✅ Data models with Hive storage
- ✅ Geocoding service (native + Nominatim fallback)
- ✅ Location service with current position
- ✅ OpenRouteService API integration
- ✅ Ride calculator with physics formulas
- ✅ Route and ride providers
- ✅ Input screen with address/coordinate support
- ✅ Simulation screen with map and real-time metrics
- ✅ Summary screen with detailed statistics
- ✅ History screen to view past rides
- ✅ Platform permissions configured

## 🔧 Setup Instructions

### 1. Add Your OpenRouteService API Key

Edit the `.env` file and replace `your_api_key_here` with your actual API key:

```
OPENROUTE_SERVICE_API_KEY=your_actual_key_here
```

Get your free API key at: https://openrouteservice.org/dev/#/signup

### 2. Update Nominatim User-Agent

Edit `lib/utils/constants.dart` and replace the email in `nominatimUserAgent`:

```dart
static const String nominatimUserAgent = 'FreeRide/1.0 (your-actual-email@example.com)';
```

### 3. Run the App

```bash
flutter pub get
flutter run
```

## 🎮 How to Use

1. **Input Screen**
   - Enter start and end locations (addresses or "lat,lng" format)
   - Or tap the location icon to use your current position
   - Tap "Get Route" to fetch the route
   - Or tap "Repeat Last Ride" to reuse your previous route

2. **Simulation Screen**
   - Tap the green play button to start the ride
   - Watch the bike marker move along the route on the map
   - See real-time metrics: speed, elevation, grade, distance, time
   - Tap pause to pause the simulation
   - Tap the red X to cancel the ride early

3. **Summary Screen**
   - View comprehensive ride statistics
   - See time, distance, speed, elevation, and performance metrics
   - Tap "Save Ride" to add to history
   - Or "Discard" to not save

4. **History Screen**
   - Access from the history icon in the app bar
   - View all past rides
   - Tap any ride to see its full summary

## ⚙️ Configuration

All configuration values are in `lib/utils/constants.dart`:

- **Base Speed**: 20 km/h (real-world cycling speed)
- **Speed Multiplier**: 10x (for faster simulation)
- **Grade Adjustment**: 10% speed change per 10% grade
- **Simulation Tick**: 100ms updates
- **Max History**: 50 saved rides

## 🏗️ Architecture

```
lib/
├── models/          # Hive data models
│   ├── saved_route.dart
│   └── ride_summary.dart
├── services/        # Business logic
│   ├── route_storage_service.dart
│   ├── geocoding_service.dart
│   ├── location_service.dart
│   ├── openroute_service.dart
│   └── ride_calculator.dart
├── providers/       # State management
│   ├── route_provider.dart
│   └── ride_provider.dart
├── screens/         # UI screens
│   ├── input_screen.dart
│   ├── simulation_screen.dart
│   ├── summary_screen.dart
│   └── history_screen.dart
├── utils/           # Constants and helpers
│   └── constants.dart
└── main.dart        # App entry point
```

## 📱 Features

### Route Management
- Geocoding with address or coordinate input
- Current location support
- Route storage and retrieval
- Custom route naming

### Simulation
- Real-time position tracking on map
- Physics-based speed calculation
  - Formula: `speed = baseSpeed × multiplier × (1 - grade × 0.1)`
  - Uphill: slower, Downhill: faster
- Live metrics display
- Pause/resume functionality
- Cancel with progress saving

### Statistics
- Time: total, moving, paused
- Distance: completed, total, percentage
- Speed: average, moving average, max, min
- Elevation: gain, loss, current, max grade
- Performance: calories burned, estimated power

### Storage
- Hive local database
- Up to 50 rides in history
- Last route quick access
- Ride history filtering

## 🔮 Future Enhancements

The app is ready for these additions:

1. **Elevation Chart** - Add fl_chart visualization in summary screen
2. **Custom Names** - Edit route names in summary screen
3. **Speed Control** - UI slider to adjust base speed
4. **Multiple Routes** - Save favorite routes library
5. **Export Data** - CSV/GPX export functionality
6. **Social Features** - Share ride summaries
7. **Challenges** - Time trials and achievements

## 🐛 Troubleshooting

**Location not working?**
- Check that location permissions are granted
- Ensure location services are enabled on your device

**Route not loading?**
- Verify your OpenRouteService API key is correct in `.env`
- Check your internet connection
- Try entering coordinates directly instead of addresses

**Geocoding fails?**
- Native geocoding may not work on emulators
- The app will fallback to Nominatim automatically
- Respect the 1 request/second rate limit for Nominatim

## 📄 License

This is a demo project. Adjust as needed for your use case.

---

**Ready to ride! 🚴‍♂️💨**
