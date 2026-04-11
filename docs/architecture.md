# Architecture

## Overview

Free Ride follows a layered architecture with clear separation of concerns. The application is built using Flutter's Provider pattern for state management, Hive for local persistence, and a service layer that encapsulates business logic, device communication, and external API integration.

## Layer Diagram

```mermaid
graph TB
    subgraph UI["UI Layer"]
        HS[HomeScreen]
        IS[InputScreen]
        SS[SimulationScreen]
        SU[SummaryScreen]
        HI[HistoryScreen]
        DS[DeviceSetupScreen]
        PS[ProfileScreen]
        W[Widgets]
    end

    subgraph State["State Management Layer"]
        RP[RouteProvider]
        RIP[RideProvider]
        DP[DeviceProvider]
    end

    subgraph Services["Service Layer"]
        subgraph Device["Device Services"]
            FD[FitnessDevice]
            VB[VirtualIndoorBike]
            VT[VirtualTreadmill]
            FTMS[FTMSDeviceService]
            ECH[EchelonDevice]
        end
        subgraph Physics["Physics & Simulation"]
            RC[RideCalculator]
            HRS[HeartRateSimulator]
            EPT[EchelonPowerTable]
        end
        subgraph Connect["Connectivity"]
            ORS[OpenRouteService]
            GCS[GeocodingService]
            LS[LocationService]
        end
        subgraph Persist["Persistence"]
            RSS[RouteStorageService]
            PRS[ProfileService]
            DSS[DeviceStorageService]
        end
    end

    subgraph Data["Data Layer"]
        SR[SavedRoute]
        RS[RideSummary]
        FTD[FTMSDevice]
        UP[UserProfile]
        DDS[DeviceDataSnapshot]
        HIVE[(Hive Boxes)]
    end

    UI --> State
    State --> Services
    Services --> Data
    Persist --> HIVE
```

## Component Interaction

```mermaid
graph LR
    subgraph User
        A[User Input]
    end

    subgraph Providers
        RP[RouteProvider]
        RIP[RideProvider]
        DP[DeviceProvider]
    end

    subgraph External
        ORS[OpenRouteService API]
        BLE[Bluetooth Devices]
        GPS[GPS/Location]
        NOM[Nominatim API]
    end

    A --> RP
    A --> DP
    A --> RIP

    RP -->|fetch route| ORS
    RP -->|geocode address| NOM
    RP -->|current location| GPS
    DP -->|scan & connect| BLE
    RIP -->|device data| DP
    RIP -->|route data| RP
```

## Design Patterns

| Pattern | Where Used | Purpose |
|---------|-----------|---------|
| **Provider (ChangeNotifier)** | RouteProvider, RideProvider, DeviceProvider | Reactive state management for UI updates |
| **Abstract Factory** | FitnessDevice interface + device detectors | Create device instances without coupling to concrete types |
| **Command Pattern** | ControlCommand sealed class (SetResistance, SetIncline) | Encapsulate device control instructions |
| **Strategy Pattern** | Device detectors list in DeviceProvider | Pluggable device detection algorithms |
| **Observer** | BLE connectionState streams | Monitor device connection for auto-reconnect |
| **Repository** | RouteStorageService, ProfileService, DeviceStorageService | Abstract data persistence behind service interfaces |
| **State Machine** | RideProvider (RideStatus enum) | Manage ride lifecycle transitions |

## State Machine: Ride Lifecycle

```mermaid
stateDiagram-v2
    [*] --> notStarted
    notStarted --> running : startRide()
    running --> paused : pauseRide()
    paused --> running : resumeRide()
    running --> completed : completeRide()
    paused --> completed : completeRide()
    running --> cancelled : cancelRide()
    paused --> cancelled : cancelRide()
    notStarted --> cancelled : cancelRide()
    completed --> [*]
    cancelled --> [*]
```

## Initialization Flow

```mermaid
sequenceDiagram
    participant M as main()
    participant E as Environment
    participant S as Storage Services
    participant P as Providers
    participant UI as HomeScreen

    M->>E: Load .env (API keys)
    M->>E: Disable BLE verbose logging
    M->>S: Init RouteStorageService
    M->>S: Init ProfileService
    M->>S: Init DeviceStorageService
    M->>P: Create MultiProvider
    Note over P: RouteProvider<br/>RideProvider<br/>DeviceProvider
    M->>UI: Launch MaterialApp → HomeScreen
    UI->>UI: Check hasProfile?
    alt No profile
        UI->>UI: Redirect to Profile tab
    end
```

## Data Flow: Route Creation to Ride Completion

```mermaid
sequenceDiagram
    participant U as User
    participant IS as InputScreen
    participant RP as RouteProvider
    participant GC as GeocodingService
    participant ORS as OpenRouteService
    participant RC as RideCalculator
    participant RSS as RouteStorageService
    participant RIP as RideProvider
    participant FD as FitnessDevice
    participant SS as SimulationScreen
    participant SU as SummaryScreen

    U->>IS: Enter start/end/waypoints
    IS->>RP: fetchRoute(start, end, waypoints)
    RP->>GC: geocode(address)
    GC-->>RP: LatLng coordinates
    RP->>ORS: getRoute(start, end, waypoints)
    ORS-->>RP: Polyline + elevations
    RP->>RC: calculateGrades(elevations, distances)
    RP->>RSS: saveRoute(route)
    RP-->>IS: Route ready

    U->>IS: Click "Start Ride"
    IS->>IS: Capture map screenshot
    IS->>RIP: startRideWithDevice(route, device, thumbnail)
    RIP->>FD: connect()
    FD-->>RIP: Connected
    IS->>SS: Navigate to SimulationScreen

    loop Every 100ms
        RIP->>FD: simulate(deltaTime, grade, intensity)
        FD-->>RIP: DeviceDataSnapshot
        RIP->>FD: sendControlCommand(resistance/incline)
        RIP->>RIP: Update position & metrics
        RIP-->>SS: notifyListeners()
    end

    RIP->>RIP: completeRide()
    RIP->>RSS: saveRideHistory(summary)
    SS->>SU: Navigate to SummaryScreen
```

## Dependency Graph

```mermaid
graph TD
    main[main.dart] --> RP[RouteProvider]
    main --> RIP[RideProvider]
    main --> DP[DeviceProvider]

    RP --> GCS[GeocodingService]
    RP --> ORS[OpenRouteService]
    RP --> RSS[RouteStorageService]
    RP --> RC[RideCalculator]

    RIP --> RC
    RIP --> RSS
    RIP --> FD[FitnessDevice]

    DP --> DSS[DeviceStorageService]
    DP --> FTMS[FTMSDeviceService]
    DP --> ECH[EchelonDevice]
    DP --> VB[VirtualIndoorBike]
    DP --> VT[VirtualTreadmill]

    VB --> HRS[HeartRateSimulator]
    VT --> HRS
    ECH --> EPT[EchelonPowerTable]

    GCS --> LS[LocationService]

    RSS --> HIVE[(Hive)]
    DSS --> HIVE
    PRS[ProfileService] --> HIVE

    ORS --> ENV[.env API Key]
    GCS --> NOM[Nominatim API]
```

## Technology Stack Diagram

```mermaid
graph LR
    subgraph Frontend
        FL[Flutter / Material 3]
        PR[Provider]
        FM[flutter_map]
        FC[fl_chart]
    end

    subgraph Backend
        HV[Hive NoSQL]
        FBP[flutter_blue_plus]
        HTTP[http package]
    end

    subgraph External
        OSM[OpenStreetMap Tiles]
        ORS[OpenRouteService API]
        NOM[Nominatim Geocoding]
        BLE[BLE Fitness Devices]
    end

    FL --> PR
    FL --> FM
    FL --> FC
    PR --> HV
    PR --> FBP
    FM --> OSM
    HTTP --> ORS
    HTTP --> NOM
    FBP --> BLE
```
