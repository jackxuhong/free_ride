# Bluetooth Integration

Free Ride supports three categories of fitness devices: virtual simulators, standard FTMS (Fitness Machine Service) devices, and Echelon proprietary bikes.

## Device Hierarchy

```mermaid
classDiagram
    class FitnessDevice {
        <<abstract>>
        +connect() Future~void~
        +disconnect() Future~void~
        +sendControlCommand(cmd) Future~void~
        +simulate(dt, grade, intensity) DeviceDataSnapshot
        +isConnected bool
        +connectionState Stream
        +deviceType DeviceType
    }

    class VirtualIndoorBike {
        -speed: double
        -resistance: double
        -HeartRateSimulator hrs
        +simulate() DeviceDataSnapshot
        +updateInputs(effort, param)
    }

    class VirtualTreadmill {
        -speed: double
        -incline: double
        -HeartRateSimulator hrs
        +simulate() DeviceDataSnapshot
        +updateInputs(effort, param)
    }

    class FTMSDeviceService {
        -BluetoothDevice bleDevice
        -characteristics: Map
        +connect() Future~void~
        +disconnect() Future~void~
        +sendControlCommand(cmd)
        +detectDevice(device)$ Future~FTMSDevice?~
    }

    class EchelonDevice {
        -BluetoothDevice bleDevice
        -EchelonPowerTable powerTable
        +connect() Future~void~
        +disconnect() Future~void~
        +detectDevice(device)$ Future~FTMSDevice?~
    }

    FitnessDevice <|-- VirtualIndoorBike
    FitnessDevice <|-- VirtualTreadmill
    FitnessDevice <|-- FTMSDeviceService
    FitnessDevice <|-- EchelonDevice
```

## Device Detection Flow

```mermaid
sequenceDiagram
    participant DP as DeviceProvider
    participant FBP as FlutterBluePlus
    participant ECH as EchelonDevice
    participant FTMS as FTMSDeviceService
    participant DSS as DeviceStorageService

    DP->>FBP: startScan(timeout: 10s)
    loop For each discovered device
        FBP-->>DP: BluetoothDevice
        DP->>DP: Check skip cache
        alt Not in cache
            DP->>ECH: detectDevice(bleDevice)
            Note over ECH: Check name prefix "ECH"<br/>Connect & validate service UUID
            alt Echelon detected
                ECH-->>DP: FTMSDevice(type: indoorBike)
                DP->>DSS: saveDevice(device)
            else Not Echelon
                DP->>FTMS: detectDevice(bleDevice)
                Note over FTMS: Query FTMS service 0x1826<br/>Check for 0x2AD2 or 0x2ACD
                alt FTMS detected
                    FTMS-->>DP: FTMSDevice(type: bike/treadmill)
                    DP->>DSS: saveDevice(device)
                else Not supported
                    DP->>DP: Add to skip cache
                end
            end
        end
    end
```

---

## FTMS Protocol

The [Fitness Machine Service (FTMS)](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/) is a Bluetooth SIG standard for fitness equipment.

### Service & Characteristics

| UUID | Name | Direction |
|------|------|-----------|
| `0x1826` | Fitness Machine Service | — |
| `0x2AD2` | Indoor Bike Data | Device → App (Notify) |
| `0x2ACD` | Treadmill Data | Device → App (Notify) |
| `0x2AD9` | Fitness Machine Control Point | App → Device (Write) |
| `0x2ACC` | Fitness Machine Feature | Device → App (Read) |

### Indoor Bike Data Packet (0x2AD2)

The packet uses a flags-based format. A 16-bit flags field indicates which optional fields are present:

```mermaid
graph LR
    subgraph Packet["Indoor Bike Data Packet"]
        F[Flags<br/>2 bytes] --> S[Speed<br/>2 bytes<br/>always]
        S --> AS[Avg Speed?<br/>2 bytes]
        AS --> C[Cadence?<br/>2 bytes]
        C --> AC[Avg Cadence?<br/>2 bytes]
        AC --> TD[Total Distance?<br/>3 bytes]
        TD --> R[Resistance?<br/>2 bytes]
        R --> P[Power?<br/>2 bytes]
        P --> AP[Avg Power?<br/>2 bytes]
        AP --> E[Energy?<br/>6 bytes]
        E --> HR[Heart Rate?<br/>1 byte]
    end
```

| Flag Bit | Field | Size | Resolution |
|----------|-------|------|------------|
| — | Instantaneous Speed | uint16 | 0.01 km/h |
| 1 | Average Speed | uint16 | 0.01 km/h |
| 2 | Instantaneous Cadence | uint16 | 0.5 RPM |
| 3 | Average Cadence | uint16 | 0.5 RPM |
| 4 | Total Distance | uint24 | 1 meter |
| 5 | Resistance Level | sint16 | 0.1 |
| 6 | Instantaneous Power | sint16 | 1 watt |
| 7 | Average Power | sint16 | 1 watt |
| 8 | Energy (total, per hour, per min) | 3×uint16 | 1 kcal |
| 9 | Heart Rate | uint8 | 1 bpm |

### Treadmill Data Packet (0x2ACD)

Similar flags-based structure with treadmill-specific fields (speed, incline, pace).

### Control Commands

| Opcode | Name | Payload | Usage |
|--------|------|---------|-------|
| `0x00` | Request Control | — | App requests control of the machine |
| `0x06` | Set Target Inclination | sint16 (0.1%) | Treadmill incline |
| `0x11` | Set Simulation Parameters | wind, grade, Crr, Cw | Indoor bike resistance via grade |

### Connection Lifecycle

```mermaid
sequenceDiagram
    participant App
    participant BLE as BLE Device

    App->>BLE: connect()
    BLE-->>App: Connected
    App->>BLE: discoverServices()
    BLE-->>App: Service list
    App->>BLE: Read Feature characteristic
    Note over App: Extract resistance/incline ranges
    App->>BLE: Subscribe to data notifications
    App->>BLE: Write Control Point (Request Control)
    BLE-->>App: Response (Success)

    loop During ride
        BLE-->>App: Data notification (speed, power, etc.)
        App->>BLE: Write Control Point (Set Resistance/Incline)
    end

    alt Device disconnects
        BLE-->>App: Disconnect event
        App->>App: Pause ride
        loop Retry with 2s backoff
            App->>BLE: connect()
            alt Success
                BLE-->>App: Connected
                App->>App: Resume ride
            end
        end
    end
```

---

## Echelon Protocol

Echelon bikes use a proprietary BLE protocol instead of standard FTMS.

### Detection

1. Check device name prefix: `"ECH"`
2. Connect and verify proprietary service UUID: `0bf669f1-45f2-11e7-9598-0800200c9a66`

### Proprietary Service UUIDs

| UUID | Purpose |
|------|---------|
| `0bf669f1-45f2-11e7-9598-0800200c9a66` | Main service |
| `0bf669f2-...` | Write characteristic |
| `0bf669f3-...` | Notify characteristic 1 |
| `0bf669f4-...` | Notify characteristic 2 |

### Connection Sequence

```mermaid
sequenceDiagram
    participant App
    participant ECH as Echelon Bike

    App->>ECH: connect()
    App->>ECH: discoverServices()
    App->>ECH: Subscribe to notify characteristics
    App->>ECH: Write init sequence (F0 A1)
    App->>ECH: Write init sequence (F0 A3)
    App->>ECH: Write init sequence (F0 B0)

    loop Every 2 seconds
        App->>ECH: Send keep-alive poll
    end

    loop On notification
        ECH-->>App: Cadence + Resistance data
        App->>App: Lookup power in EchelonPowerTable
    end
```

### Resistance Mapping

Echelon uses a 1–32 resistance scale. The app maps this to the FTMS 1–20 scale:

$$R_{FTMS} = \frac{R_{Echelon} - 1}{1.55} + 1$$

### Power Calculation

Since Echelon bikes don't report power, the `EchelonPowerTable` provides a lookup table:
- 33 resistance levels × 11 cadence ranges
- Linear interpolation between cadence range boundaries
- Validated against Echelon Connect Sport hardware

---

## Virtual Devices

Virtual devices provide physics-based simulation without real hardware. Two virtual devices are created on first app launch.

### Virtual Indoor Bike

| Parameter | Range | Default |
|-----------|-------|---------|
| Speed | 0–50 km/h | 20 km/h |
| Resistance | 1–20 | 1 |

Auto-resistance based on route grade:
- Grade mapped to resistance 1–20
- Adjusts power, cadence, and HR accordingly

### Virtual Treadmill

| Parameter | Range | Default |
|-----------|-------|---------|
| Speed | 0–25 km/h | 8 km/h |
| Incline | -3% to +15% | 0% |

Auto-incline based on route grade:
- Smoothed at 2%/sec to prevent jarring changes
- Adjusts pace, power, and HR accordingly

---

## Auto-Reconnect

When a real BLE device disconnects during a ride:

```mermaid
flowchart TD
    DC[Device Disconnects] --> PAUSE[Pause Ride]
    PAUSE --> BANNER[Show Reconnecting Banner]
    BANNER --> RETRY[Attempt Reconnect]
    RETRY --> WAIT[Wait 2 seconds]
    WAIT --> CHECK{Connected?}
    CHECK -->|No| RETRY
    CHECK -->|Yes| REDISCOVER[Rediscover Services]
    REDISCOVER --> RESUB[Resubscribe to Notifications]
    RESUB --> RESUME[Resume Ride]
```

- Applies to both FTMS and Echelon devices
- 2-second backoff between attempts
- Ride remains paused during reconnection
- UI displays a yellow "Reconnecting..." banner
