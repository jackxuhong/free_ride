# State Management

Free Ride uses [Provider](https://pub.dev/packages/provider) with `ChangeNotifier` for reactive state management. Three providers are registered at the app root via `MultiProvider` and are accessible throughout the widget tree.

## Provider Architecture

```mermaid
graph TD
    subgraph MultiProvider["MultiProvider (main.dart)"]
        RP[RouteProvider]
        RIP[RideProvider]
        DP[DeviceProvider]
    end

    subgraph Screens
        IS[InputScreen]
        SS[SimulationScreen]
        SU[SummaryScreen]
        HI[HistoryScreen]
        DS[DeviceSetupScreen]
        PS[ProfileScreen]
    end

    IS -->|watch/read| RP
    IS -->|read| DP
    IS -->|read| RIP
    SS -->|watch| RIP
    SS -->|watch| DP
    SU -->|read| RIP
    HI -->|read| RSS[RouteStorageService]
    DS -->|watch| DP
    PS -->|read| PRS[ProfileService]
```

---

## RouteProvider

**File:** `lib/providers/route_provider.dart`

Manages the lifecycle of route creation, loading, and storage. Orchestrates geocoding, API calls, and persistence.

### State

| Field | Type | Description |
|-------|------|-------------|
| `_currentRoute` | SavedRoute? | Currently loaded/created route |
| `_isLoading` | bool | Whether a route fetch is in progress |
| `_error` | String? | Error message from last operation |

### Methods

| Method | Purpose |
|--------|---------|
| `fetchRoute(start, end, waypoints?)` | Geocode inputs → fetch from OpenRouteService → calculate grades → save |
| `loadRoute(route)` | Load an existing saved route into state |
| `setCurrentRoute(route)` | Set route directly (for repeating rides) |
| `clearRoute()` | Clear the current route |
| `updateRouteName(customName)` | Rename via storage service |

### Flow: Route Fetching

```mermaid
sequenceDiagram
    participant UI as InputScreen
    participant RP as RouteProvider
    participant GCS as GeocodingService
    participant ORS as OpenRouteService
    participant RC as RideCalculator
    participant RSS as RouteStorageService

    UI->>RP: fetchRoute(startText, endText, waypointTexts)
    RP->>RP: _isLoading = true
    RP->>GCS: geocode(startText)
    GCS-->>RP: startLatLng
    RP->>GCS: geocode(endText)
    GCS-->>RP: endLatLng
    loop Each waypoint
        RP->>GCS: geocode(waypointText)
        GCS-->>RP: waypointLatLng
    end
    RP->>ORS: getRoute(start, end, waypoints)
    ORS-->>RP: raw route data
    RP->>ORS: parseRouteData(data)
    ORS-->>RP: coordinates + elevations
    RP->>RC: calculateGrades(elevations, distances)
    RC-->>RP: grades[]
    RP->>RP: Build SavedRoute object
    RP->>RSS: saveRoute(route)
    RP->>RP: _currentRoute = route
    RP->>RP: _isLoading = false
    RP->>UI: notifyListeners()
```

---

## DeviceProvider

**File:** `lib/providers/device_provider.dart`

Manages BLE device scanning, detection, selection, and lifecycle. Maintains both the persisted device descriptor (`FTMSDevice` model) and the active device instance (`FitnessDevice` interface).

### State

| Field | Type | Description |
|-------|------|-------------|
| `_selectedDevice` | FTMSDevice? | Persisted device model descriptor |
| `_activeDevice` | FitnessDevice? | Live device instance (virtual or BLE) |
| `_selectedHRMonitor` | FTMSDevice? | Selected HR monitor model |
| `_activeHRMonitor` | HeartRateMonitorService? | Live HR monitor instance |
| `_isScanning` | bool | Whether a BLE scan is active |
| `_availableDevices` | List\<FTMSDevice\> | All saved devices (exercise + HR monitors) |
| `_deviceCache` | Set\<String\> | BLE addresses already tested (skip on rescan) |

### Device Detection Pipeline

```mermaid
flowchart TD
    A[Start BLE Scan] --> B[Discover BLE Device]
    B --> C{In cache?}
    C -->|Yes| B
    C -->|No| D[Try Echelon Detector]
    D -->|Match| E[Save Echelon Device]
    D -->|No match| F[Try FTMS Detector]
    F -->|Match| G[Save FTMS Device]
    F -->|No match| I[Try HR Monitor Detector]
    I -->|Match| J[Save HR Monitor Device]
    I -->|No match| H[Add to skip cache]
    E --> B
    G --> B
    J --> B
    H --> B
```

### Device Factory

```mermaid
flowchart TD
    SD[selectDevice] --> CHECK{isVirtual?}
    CHECK -->|Yes| VTYPE{deviceType?}
    VTYPE -->|indoorBike| VB[VirtualIndoorBike]
    VTYPE -->|treadmill| VT[VirtualTreadmill]
    CHECK -->|No| RTYPE{Detection type?}
    RTYPE -->|Echelon name| ECH[EchelonDevice]
    RTYPE -->|Standard FTMS| FTMS[FTMSDeviceService]
```

### Methods

| Method | Purpose |
|--------|---------|
| `init()` | Load saved devices + last used device + last used HR monitor |
| `selectDevice(device)` | Set active device, create FitnessDevice instance (routes HR monitors to `selectHRMonitor`) |
| `selectHRMonitor(device)` | Set active HR monitor, create HeartRateMonitorService instance |
| `deselectHRMonitor()` | Disconnect and clear active HR monitor |
| `startScan()` | 10-sec BLE scan; test each with detectors (Echelon, FTMS, HR Monitor); save new devices |
| `stopScan()` | Stop active BLE scan |
| `deleteDevice(id)` | Remove device from storage |
| `updateDeviceParameters(effort, param)` | Update effort level / controllable parameter |
| `clearDeviceCache()` | Force rescan of all devices |

---

## RideProvider

**File:** `lib/providers/ride_provider.dart`

The most complex provider. Manages the ride state machine, simulation loop, position tracking, metrics aggregation, and ride completion.

### State Machine

```mermaid
stateDiagram-v2
    [*] --> notStarted : initializeRide()
    notStarted --> running : startRide()
    running --> paused : pauseRide()
    running --> paused : device disconnects
    paused --> running : resumeRide()
    paused --> running : device reconnects
    running --> completed : route end reached
    running --> completed : completeRide()
    paused --> completed : completeRide()
    running --> cancelled : cancelRide()
    paused --> cancelled : cancelRide()
    notStarted --> cancelled : cancelRide()
    completed --> [*]
    cancelled --> [*]
```

### State Fields

**Position:**

| Field | Type | Description |
|-------|------|-------------|
| `_currentSegmentIndex` | int | Index of the current route segment |
| `_progressInSegment` | double | 0.0–1.0 progress within current segment |
| `_currentPosition` | LatLng | Interpolated rider position |
| `_currentBearing` | double | Direction of travel (degrees) |

**Time:**

| Field | Type | Description |
|-------|------|-------------|
| `_totalDuration` | Duration | Wall-clock elapsed |
| `_movingTime` | Duration | Time spent moving |
| `_pausedTime` | Duration | Time spent paused |
| `_startTime` | DateTime? | Ride start timestamp |

**Metrics:**

| Field | Type | Description |
|-------|------|-------------|
| `_completedDistance` | double | Distance covered (meters) |
| `_currentSpeed` | double | Current speed (km/h) |
| `_maxSpeed` / `_minSpeed` | double | Speed extremes |
| `_speedSamples` | List\<double\> | For averaging |
| `_currentElevation` | double | Interpolated elevation |
| `_elevationGain` / `_elevationLoss` | double | Accumulated climb/descent |
| `_currentPower` | double | Current power (watts) |
| `_powerSamples` | List\<PowerSample\> | Timestamped power readings |
| `_currentCadence` | double | Current cadence/pace |
| `_currentHeartRate` | int | Current HR (bpm) |
| `_hrMonitor` | HeartRateMonitorService? | Optional standalone HR monitor |
| `_caloriesBurned` | double | Running calorie total |
| `_workoutIntensity` | double | 0.5–2.0 multiplier |

### Simulation Loop

The ride runs a timer at 100ms intervals:

```mermaid
flowchart TD
    TICK[Timer Tick - 100ms] --> STATUS{RideStatus?}
    STATUS -->|running| DEVICE[Get DeviceDataSnapshot]
    STATUS -->|other| SKIP[Skip]

    DEVICE --> CONTROL[Send ControlCommand to device]
    CONTROL --> CALC[Calculate distance moved]
    CALC --> POS[Update position on route]
    POS --> ELEV[Interpolate elevation]
    ELEV --> METRICS[Update all metrics]
    METRICS --> CHECK{End of route?}
    CHECK -->|Yes| COMPLETE[completeRide]
    CHECK -->|No| NOTIFY[notifyListeners]
```

### Key Methods

| Method | Purpose |
|--------|---------|
| `initializeRide(route, thumbnail?)` | Setup ride state without device |
| `startRideWithDevice(route, device, thumbnail?, hrMonitor?)` | Full setup: connect device + optional HR monitor + start |
| `startRide()` | Begin simulation loop |
| `pauseRide()` | Pause timer and metrics |
| `resumeRide()` | Resume from pause |
| `completeRide()` | Generate RideSummary, save to history |
| `cancelRide()` | Generate summary with cancellation reason |
| `setWorkoutIntensity(value)` | Set 0.5×–2.0× intensity multiplier |

### Metrics Calculation

On each 100ms tick:

1. **Speed** — from device data or calculated from base speed + grade adjustment
2. **Distance** — `speed × deltaTime`
3. **Position** — interpolate along route segments
4. **Elevation** — interpolate between segment elevation values
5. **Power** — from device data or estimated via RideCalculator
6. **Calories** — accumulated via RideCalculator.estimateCalories
7. **Heart Rate** — from device data
7. **Heart Rate** — from HR monitor (highest priority), device data, or simulated

### Provider Communication

```mermaid
graph LR
    DP[DeviceProvider] -->|activeDevice| RIP[RideProvider]
    DP -->|activeHRMonitor| RIP
    RP[RouteProvider] -->|currentRoute| RIP
    RIP -->|notifyListeners| SS[SimulationScreen]
    RIP -->|rideSummary| RSS[RouteStorageService]
    RIP -->|rideSummary| SU[SummaryScreen]
```
