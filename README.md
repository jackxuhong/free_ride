# Free Ride

A Flutter application that simulates outdoor running, walking, and cycling experiences indoors. Connect a treadmill, stationary bike, or elliptical via Bluetooth, plan a route with real-world elevation data, and ride it virtually — the app adjusts resistance or incline to match the terrain in real time.

## Features

### Bluetooth Device Support
- **FTMS Standard** — connects to any Fitness Machine Service–compliant indoor bike or treadmill (resistance and incline control)
- **Echelon Proprietary** — auto-detects Echelon Connect Sport bikes by name prefix and verifies via proprietary service UUIDs; maps Echelon resistance (1–32) to FTMS standard (1–20); power estimation via a 33×11 lookup table with interpolation
- **Virtual Devices** — built-in virtual indoor bike and virtual treadmill for ride simulation without hardware; physics-based speed, power, cadence, and heart rate modelling
- **Auto-Reconnection** — reconnects automatically if a Bluetooth device drops during a ride

### Route Planning
- Multi-stop waypoint routes with address or `lat,lng` coordinate input
- Current-location button (GPS)
- Geocoding via native platform APIs with Nominatim fallback (1 req/s rate-limited)
- Cycling-optimised routes with elevation data from [OpenRouteService](https://openrouteservice.org)
- Route difficulty classification (Easy / Moderate / Hard) based on elevation gain per km
- Route thumbnail capture, save, load, edit, and rename

### Ride Simulation
- Animated rider marker on a live `flutter_map` map
- Grade-adjusted speed: `speed = baseSpeed × multiplier × (1 − grade × 0.1)`
- Real-time metrics dashboard: speed, distance, elevation, grade, cadence, heart rate, power
- Play / pause / cancel controls with navigation vs. overview map modes
- Adjustable workout intensity multiplier
- Wakelock keeps the screen on during rides

### Heart Rate Simulation
- Exponential approach to a target HR based on effort and intensity
- Asymmetric rise / recovery rates with ±2 bpm random variability
- HR zone calculation (zones 1–5)

### Performance Tracking
- 27+ ride metrics: time (total / moving / paused), distance, speed (avg / moving / max / min), elevation (gain / loss / max grade), power (avg watts), calories, cadence, heart rate, completion percentage
- Ride history persisted locally (up to 50 rides)
- Post-ride summary screen with save / delete / replay options
- Resume or restart past rides from history

### User Profile
- Name, email, and body weight stored locally
- Body weight feeds calorie and power calculations
- Email used as Nominatim User-Agent

## Getting Started

### Prerequisites

- Flutter SDK ≥ 3.10.4
- An [OpenRouteService API key](https://openrouteservice.org/dev/#/signup) (free tier available)

### Installation

```bash
git clone <repository-url>
cd free_ride
flutter pub get
dart run build_runner build     # generate Hive type adapters
```

### Configuration

Create a `.env` file in the project root:

```
OPENROUTE_SERVICE_API_KEY=your_api_key_here
```

### Running

```bash
flutter run -d <device>
```

### Physics Constants

Simulation parameters live in `lib/utils/constants.dart`:

| Constant | Default | Description |
|----------|---------|-------------|
| `baseSpeedKmh` | 20.0 | Base riding speed in km/h |
| `speedMultiplier` | 10.0 | Simulation speed multiplier |
| `gradeAdjustmentFactor` | 0.1 | Speed reduction per 1 % grade |
| `defaultBodyWeightKg` | 70.0 | Fallback body weight for calculations |

## Architecture

### Project Layout

```
lib/
├── main.dart                         # entry point — Hive, dotenv, Provider setup
├── models/
│   ├── saved_route.dart              # route with geometry & elevation (Hive types 0–4)
│   ├── ride_summary.dart             # 27-field ride statistics     (Hive type 6)
│   ├── user_profile.dart             # name, email, body weight     (Hive type 7)
│   ├── ftms_device.dart              # persisted device descriptor   (Hive types 8–9)
│   ├── device_data_snapshot.dart     # point-in-time device reading  (not persisted)
│   └── duration_adapter.dart         # Duration ↔ microseconds      (Hive type 100)
├── providers/
│   ├── route_provider.dart           # geocoding → API → parse → save workflow
│   ├── ride_provider.dart            # ride state machine & simulation loop
│   └── device_provider.dart          # BLE scanning, device creation & selection
├── screens/
│   ├── home_screen.dart              # bottom-nav shell (Routes, History, Devices, Profile)
│   ├── input_screen.dart             # route creation with map preview
│   ├── simulation_screen.dart        # live ride with map, metrics, controls
│   ├── summary_screen.dart           # post-ride statistics
│   ├── history_screen.dart           # saved ride list
│   ├── device_setup_screen.dart      # BLE scanning & virtual device management
│   └── profile_screen.dart           # user profile form
├── services/
│   ├── fitness_device.dart           # abstract FitnessDevice interface
│   ├── ftms_device_service.dart      # real FTMS BLE device
│   ├── echelon_device.dart           # Echelon proprietary BLE device
│   ├── echelon_power_table.dart      # Echelon power lookup table
│   ├── virtual_indoor_bike.dart      # virtual bike simulator
│   ├── virtual_treadmill.dart        # virtual treadmill simulator
│   ├── virtual_device_interface.dart # ControlCommand sealed class
│   ├── heart_rate_simulator.dart     # HR dynamics model
│   ├── openroute_service.dart        # OpenRouteService API client
│   ├── geocoding_service.dart        # address ↔ LatLng (native + Nominatim)
│   ├── location_service.dart         # Geolocator wrapper
│   ├── ride_calculator.dart          # speed, power, calorie calculations
│   ├── route_storage_service.dart    # Hive CRUD for routes & rides
│   ├── profile_service.dart          # Hive user profile persistence
│   └── device_storage_service.dart   # Hive device persistence
├── utils/
│   └── constants.dart                # app-wide constants & helpers
└── widgets/
    ├── elevation_chart.dart          # fl_chart elevation profile
    ├── device_connection_widget.dart  # connected-device status badge
    └── virtual_device_controller.dart # speed slider for virtual devices
```

### State Management

Three `ChangeNotifier` providers exposed via `MultiProvider`:

| Provider | Responsibility |
|----------|---------------|
| `RouteProvider` | Route lifecycle: geocode → fetch → parse → store |
| `RideProvider` | Ride state machine (not started → running → paused → completed / cancelled), simulation timer, metric aggregation |
| `DeviceProvider` | BLE scanning with pluggable detectors, device instantiation (`VirtualIndoorBike`, `VirtualTreadmill`, `FTMSDevice`, `EchelonDevice`), parameter updates |

### Device Architecture

`FitnessDevice` is an abstract interface; adding a new protocol requires implementing the interface and registering a detector in `DeviceProvider`:

```
FitnessDevice (abstract)
├── VirtualIndoorBike     — physics-based bike simulation
├── VirtualTreadmill      — physics-based treadmill simulation
├── FTMSDevice            — real BLE device (FTMS standard)
└── EchelonDevice         — real BLE device (Echelon proprietary)
```

### Local Storage

Hive NoSQL with type-safe adapters (type IDs 0–9, 100). Three boxes:

| Box | Contents |
|-----|----------|
| `saved_routes` | `SavedRoute` models with geometry and elevation profiles |
| `ride_history` | `RideSummary` records (capped at 50) |
| `settings` | Key-value pairs (last route ID, etc.) |

Separate boxes for `UserProfile` and `FTMSDevice` persistence.

## Platform Notes

| Platform | Notes |
|----------|-------|
| **iOS / Android** | Location permissions required for "Use Current Location". BLE permissions for device connectivity. |
| **macOS** | Network-client entitlement already configured. Native geocoding skipped — Nominatim used instead. |
| **Linux / Windows / Web** | Map and simulation features work; BLE not available on all platforms. |

## Dependencies

### Runtime

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_map` | ^7.0.2 | Interactive map display |
| `latlong2` | ^0.9.1 | Geographic coordinate types |
| `fl_chart` | ^0.69.0 | Elevation chart visualisation |
| `geolocator` | ^13.0.2 | GPS location services |
| `permission_handler` | ^11.3.1 | Runtime permission management |
| `geocoding` | ^3.0.0 | Address ↔ coordinate conversion |
| `flutter_blue_plus` | ^1.32.0 | Bluetooth Low Energy connectivity |
| `http` | ^1.2.0 | HTTP requests |
| `flutter_dotenv` | ^5.2.1 | Environment variable loading |
| `provider` | ^6.1.2 | State management |
| `hive` | ^2.2.3 | Local NoSQL storage |
| `hive_flutter` | ^1.1.0 | Hive Flutter integration |
| `uuid` | ^4.3.3 | Unique ID generation |
| `intl` | ^0.19.0 | Number / date formatting |
| `wakelock_plus` | ^1.2.8 | Screen-on during rides |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |

### Development

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Unit & widget testing |
| `flutter_lints` | ^6.0.0 | Lint rules |
| `hive_generator` | ^2.0.1 | Hive adapter code generation |
| `build_runner` | ^2.4.8 | Code generation runner |

## Testing

```bash
flutter test
```

Tests cover ride physics calculations, FTMS data packet parsing, and Echelon power table lookups. Test files:

- `test/ride_calculator_test.dart` — speed, grade, elevation, power, and calorie calculations
- `test/ftms_parser_test.dart` — Indoor Bike Data and Treadmill Data bit-field parsing
- `test/echelon_power_table_test.dart` — power lookup, interpolation, and edge cases

## Known Limitations

- Echelon support is tested with Connect Sport bikes; other Echelon models may require additional service UUIDs
- BLE connectivity is not available on Web or Linux desktop
- Nominatim fallback geocoding is rate-limited to 1 request per second
- Ride history is capped at 50 entries (oldest entries are removed automatically)
