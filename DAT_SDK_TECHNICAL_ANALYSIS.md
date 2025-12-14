# Meta DAT SDK Technical Analysis

This document details the connection lifecycle, protocols, and technical limitations of the Meta Direct Access (DAT) SDK as implemented in the CameraAccess sample app.

## 1. Connection Lifecycle

The connection process involves four distinct phases:

### Phase 1: Bluetooth LE Discovery (Finding Glasses)

- **Protocol**: Bluetooth Low Energy (BLE)
- **Service UUID**: `com.meta.ar.wearable` (Broadcast in advertisement packets)
- **Mechanism**: 
  - `CBCentralManager` scans for peripherals with the target service UUID.
  - **Connection Parameters**:
    - Interval: 7.5-30ms (Fast connection)
    - Latency: 0-499
    - Timeout: 6 seconds

### Phase 2: Authentication (OAuth Flow)

- **Mechanism**: App-to-App deep linking
- **Flow**:
  1. SDK initiates registration (`wearables.startRegistration()`).
  2. Opens Meta AI app (`fb-viewapp://`).
  3. User confirms device in Meta AI app.
  4. App returns with auth code via deep link (`cameraaccess://?code=...`).
  5. SDK exchanges code for tokens:
     - `accessToken`: JWT for API calls
     - `refreshToken`: For maintaining session
     - `deviceId`: Unique glasses ID

### Phase 3: QUIC Tunnel Establishment

- **Protocol**: QUIC over L2CAP (over BLE)
- **Purpose**: To provide a reliable, multiplexed transport layer over the unreliable, limited BLE radio.
- **Layers**:
  - **L2CAP**: Logical Link Control and Adaptation Protocol (provides higher throughput channels).
  - **QUIC**: Adds reliability, congestion control, and stream multiplexing (streams for Control, Video, Photo).
  - **ALPN**: "meta-wearables-v1" protocol negotiation.
  - **Multiplexing**: Stream 0 (Control), Stream 1 (Video), Stream 2 (Photo).

**Common "Errors" During Handshake:**
- `nw_connection_copy_connected_*`: Normal polling during connection setup.
- `quic_conn_process_inbound unable to parse`: Packets arriving before handshake completes (normal).

### Phase 4: Video Streaming

- **Transport**: Video frames are packetized and sent over a specific QUIC stream (`video-stream`).
- **Data Flow**: Camera → Encode → Packetize → QUIC → L2CAP → BLE → iPhone → Reassemble → Decode → Display.

---

## 2. The "Low Quality" Reality

While the architecture uses advanced protocols (QUIC), the physical layer (Bluetooth LE) imposes severe constraints.

### The Config vs. Physics

The sample app configuration typically requests:
```swift
let config = StreamSessionConfig(
    videoCodec: .raw,        // Uncompressed (Massive size!)
    resolution: .low,        // 640x480
    frameRate: 24            // 24fps
)
```

**The Math (Why it lags):**
- **Required Bandwidth** (Raw 640x480 @ 24fps): ~22 Mbps
- **Available BLE Bandwidth**: ~0.5 - 2 Mbps
- **Deficit**: The video needs **10x-40x** more bandwidth than available.

### Real-World Result

- **Frame Drops**: Massive dropping to fit the pipe (resulting in 5-15 fps).
- **Compression**: SDK likely forces fallback to heavy compression (MJPEG/H.264) or drops resolution further.
- **Latency**: Buffering delays of 1-3 seconds.
- **Artifacts**: Blockiness and tearing due to packet loss/congestion.

### Why "QUIC over BLE"?

The use of QUIC isn't for speed (BLE limits that), but for **reliability**:
- Handles packet loss better than raw GATT notifications.
- Prevents head-of-line blocking (audio doesn't stop if video drops).
- Manages congestion to keep the connection alive despite saturation.

---

## 3. Conclusion

The CameraAccess app demonstrates **connectivity**, not high-fidelity streaming. It proves the ability to establish a secure data tunnel to the glasses, but the video capability is valid mostly for "preview" use cases, not high-quality capture. The bottleneck is the fundamental physics of the Bluetooth 2.4GHz radio.
