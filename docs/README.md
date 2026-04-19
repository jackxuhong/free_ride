# Free Ride Documentation

**Free Ride** is a Flutter-based indoor exercise simulator that lets users ride virtual outdoor routes on treadmills, stationary bikes, or ellipticals. It connects to exercise equipment via Bluetooth (BLE), provides real-time simulation with terrain-based resistance/incline adjustments, and tracks comprehensive workout metrics.

## Table of Contents

| Document | Description |
|----------|-------------|
| [Architecture](architecture.md) | High-level system architecture, layer structure, and key design patterns |
| [Data Models](data-models.md) | All persistent and transient data models with field-level detail |
| [State Management](state-management.md) | Provider-based state management, the three providers, and state flows |
| [Services](services.md) | Business logic services: device interfaces, physics, connectivity, persistence |
| [Bluetooth Integration](bluetooth-integration.md) | BLE device detection, FTMS protocol, Echelon support, and virtual devices |
| [Simulation Engine](simulation-engine.md) | Ride simulation loop, physics calculations, and metrics tracking |
| [Screens & Widgets](screens-and-widgets.md) | UI layer: screens, navigation, and reusable widgets |

## Technology Stack

| Category | Technology |
|----------|------------|
| Language | Dart 3.10.4+ |
| Framework | Flutter (Material 3) |
| State Management | Provider (ChangeNotifier) |
| Local Storage | Hive (NoSQL) |
| Bluetooth | flutter_blue_plus (BLE) |
| Maps | flutter_map + OpenStreetMap |
| Charts | fl_chart |
| Routing API | OpenRouteService |
| Geocoding | Native + Nominatim (OpenStreetMap) |

## Quick Start

```bash
# Install dependencies
flutter pub get

# Generate Hive type adapters
dart run build_runner build

# Run tests
flutter test

# Run the app
flutter run -d <device>
```

## Project Structure

```
lib/
├── main.dart                 # App entry point, provider setup
├── models/                   # Hive-persisted data models
│   ├── saved_route.dart      # Route, coordinates, geometry, elevation
│   ├── ride_summary.dart     # 27-field ride metrics
│   ├── ftms_device.dart      # Device descriptor + DeviceType enum
│   ├── user_profile.dart     # User profile
│   ├── device_data_snapshot.dart  # Transient device reading
│   └── duration_adapter.dart # Hive adapter for Duration
├── providers/                # ChangeNotifier state management
│   ├── route_provider.dart   # Route lifecycle
│   ├── ride_provider.dart    # Ride state machine & simulation
│   └── device_provider.dart  # BLE scanning & device management
├── services/                 # Business logic layer
│   ├── fitness_device.dart   # Abstract device interface
│   ├── virtual_indoor_bike.dart
│   ├── virtual_treadmill.dart
│   ├── ftms_device_service.dart  # FTMS BLE protocol
│   ├── echelon_device.dart       # Echelon proprietary BLE
│   ├── echelon_power_table.dart  # Cadence→power lookup
│   ├── heart_rate_simulator.dart
│   ├── ride_calculator.dart      # Physics & math
│   ├── openroute_service.dart    # Route API client
│   ├── geocoding_service.dart    # Address ↔ coordinates
│   ├── location_service.dart     # GPS wrapper
│   ├── route_storage_service.dart
│   ├── profile_service.dart
│   ├── device_storage_service.dart
│   └── virtual_device_interface.dart  # Control commands
├── screens/                  # Full-screen UI pages
│   ├── home_screen.dart      # Bottom navigation shell
│   ├── input_screen.dart     # Route planning
│   ├── simulation_screen.dart # Live ride
│   ├── summary_screen.dart   # Post-ride stats
│   ├── history_screen.dart   # Past rides
│   ├── device_setup_screen.dart # Device management
│   └── profile_screen.dart   # User profile form
├── widgets/                  # Reusable UI components
│   ├── elevation_chart.dart
│   ├── device_connection_widget.dart
│   └── virtual_device_controller.dart
└── utils/
    └── constants.dart        # App-wide configuration
```
