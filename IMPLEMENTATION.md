# Implementation Notes

> See [README.md](README.md) for full project documentation, architecture overview, and setup instructions.

## Recent Fixes

### Echelon Connection Stability
- Replaced fragile BLE re-scan during connection with `BluetoothDevice.fromId()` (matches FTMS approach)
- Added `orElse` to all `firstWhere` calls to surface clear errors instead of unhandled `StateError`
- Added Echelon service UUID validation during device detection (brief connect-and-verify rather than name-only check)
- Added auto-reconnection logic matching FTMS implementation
- Fixed `StreamController` dispose race condition using flag-based guard

### FTMS Data Parsing
- Rewrote `_parseIndoorBikeData` and `_parseTreadmillData` to consume **all** bit-flagged fields in order per the FTMS specification, preventing byte-offset corruption when intermediate flags are set

### Architecture Improvements
- `startRideWithDevice` changed from `void` to `Future<void>` with error handling
- Reconnection banner now works for all real device types (FTMS and Echelon), not just FTMS
- Renamed `lib/services/ftms_device.dart` → `lib/services/ftms_device_service.dart` to resolve naming collision with the Hive model
- `ElevationProfile.totalDistance` now returns actual distance (was hardcoded to `0.0`, making difficulty always "Unknown")
- Timer race condition in `completeRide` fixed with `_completing` guard flag
- `_resetMetrics` now disconnects active device before nulling the reference
- Hive adapter registrations guarded with `isAdapterRegistered()` checks
- Virtual device speed slider range reduced from 0–200 to 0–50 km/h

### Constants & Consistency
- Extracted `defaultBodyWeightKg` (70.0) and `mapUserAgentPackageName` constants
- Added shared `formatDuration` utility to eliminate duplicate implementations
- Removed hardcoded personal email from Nominatim User-Agent

### History & Replay
- "Continue Ride" and "Restart Ride" in history screen now use the active connected device

### Tests
- Added `test/ride_calculator_test.dart` — speed, grade, elevation, power, calorie calculations
- Added `test/ftms_parser_test.dart` — Indoor Bike Data and Treadmill Data parsing with various flag combinations
- Added `test/echelon_power_table_test.dart` — power lookup, interpolation, edge cases
