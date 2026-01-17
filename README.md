# Free Ride

- a mobile application that provides the ability to simulate an outdoor running/walking/cycling experience indoors using a treadmill, stationary bike, or elliptical machine.
- integration with elevation data to adjust the resistance or incline of the exercise equipment based on virtual terrain.
- The application connects to exercise equipment via Bluetooth to monitor and control workout parameters.
- It features virtual routes, real-time stats, and customizable workout intensity.
- The app aims to enhance indoor workouts by making them more engaging and realistic, or allowing users to train for outdoor events regardless of weather conditions.

## Features

- **Route Generation**: Enter addresses or coordinates to fetch routes with elevation data from OpenRouteService
- **Elevation-Based Physics**: Rider speed adjusts based on grade (±10% per 10% grade)
- **Real-Time Simulation**: Animated rider with live metrics (speed, elevation, grade, distance)
- **Comprehensive Statistics**: Track calories, power output, duration, and completion percentage
- **Ride History**: Save and review up to 50 past rides
- **Cross-Platform**: Runs on iOS, Android, macOS, Linux, Windows, and Web

## Setup

### Prerequisites

- Flutter SDK 3.10.4 or later
- Dart 3.10.0 or later
- OpenRouteService API key (free at [openrouteservice.org](https://openrouteservice.org/dev/#/signup))

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd free_ride
```

2. Install dependencies:
```bash
flutter pub get
```

3. Generate Hive type adapters:
```bash
dart run build_runner build
```

4. Configure environment variables:
```bash
cp .env.example .env
# Edit .env and add your OpenRouteService API key
```

5. Run the app:
```bash
flutter run -d <device>
```

## Configuration

### Environment Variables

Create a `.env` file in the project root with:

```
OPENROUTE_SERVICE_API_KEY=your_api_key_here
```

### Physics Constants

Edit `lib/utils/constants.dart` to adjust simulation parameters:

- `baseSpeedKmh`: Base riding speed (default: 20 km/h)
- `speedMultiplier`: Simulation speed multiplier (default: 10x)
- `gradeAdjustmentFactor`: Speed reduction per grade percentage (default: 0.1)

## Architecture

### State Management
- **Provider**: For route and ride state management
- **ChangeNotifier**: For reactive UI updates

### Local Storage
- **Hive**: NoSQL database for routes and ride history
- Type-safe adapters for custom models

### Services
- `OpenRouteService`: Route fetching and elevation data
- `GeocodingService`: Address to coordinate conversion (with Nominatim fallback)
- `RideCalculator`: Physics calculations (speed, power, calories)
- `RouteStorageService`: Hive database management

### Models
- `SavedRoute`: Route geometry and elevation profiles
- `RideSummary`: Comprehensive ride statistics (23 metrics)

## Platform-Specific Notes

### macOS
- Network client entitlement required (already configured)
- Native geocoding may be unreliable; app uses Nominatim as fallback

### iOS/Android
- Location permissions required for "Use Current Location" feature

## Dependencies

- **flutter_map 7.0.2**: Interactive map display
- **hive 2.2.3**: Local storage
- **provider 6.1.2**: State management
- **http 1.2.0**: API requests
- **geolocator 13.0.2**: Location services
- **geocoding 3.0.0**: Address conversion
- **fl_chart 0.69.0**: Data visualization
- **flutter_dotenv 5.2.1**: Environment variables

## License

MIT License - See LICENSE file for details
