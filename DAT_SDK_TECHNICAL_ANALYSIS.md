# Meta DAT SDK Technical Analysis

This document details the connection lifecycle, protocols, and technical limitations of the Meta Direct Access (DAT) SDK as implemented in the CameraAccess sample app.

## 1. Connection Lifecycle

The connection process involves four distinct phases:

### Phase 1: Bluetooth LE Discovery (Finding Glasses)

- **Protocol**: Bluetooth Low Energy (BLE)
- **Service UUID**: `com.meta.ar.wearable` (Broadcast in advertisement packets)
- **Mechanism**: 
  - `CBCentralManager` scans for peripherals with the target service UUID.
  - Device identification via advertisement data analysis.
  - Connection intervals typically configured for 7.5-30ms.

### Phase 2: Authentication (OAuth Flow)

- **Mechanism**: App-to-App deep linking
- **Flow**:
  1. SDK initiates registration (`wearables.startRegistration()`).
  2. Opens Meta AI app (`fb-viewapp://`).
  3. User confirms device in Meta AI app.
  4. App returns with auth code via deep link (`cameraaccess://?code=...`).
  5. SDK exchanges code for long-lived tokens (Access/Refresh/Device ID).
  6. Tokens stored securely in Keychain.

### Phase 3: QUIC Tunnel Establishment

- **Protocol**: QUIC over L2CAP (over BLE)
- **Purpose**: To provide a reliable, multiplexed transport layer over the unreliable, limited BLE radio.
- **Layers**:
  - **L2CAP**: Logical Link Control and Adaptation Protocol (provides higher throughput channels).
  - **QUIC**: Adds reliability, congestion control, and stream multiplexing (streams for Control, Video, Photo).
  - **ALPN**: "meta-wearables-v1" protocol negotiation.
- **Handshake**: TLS 1.3 handshake occurs over the L2CAP channel. Errors visible in logs often relate to this handshake or packet fragmentation.

### Phase 4: Video Streaming

- **Transport**: Video frames are packetized and sent over a specific QUIC stream (`video-stream`).
- **Data Flow**: Camera → Encode → Packetize → QUIC → L2CAP → BLE → iPhone → Reassemble → Decode → Display.

---

## 2. Technical Limitations & Reality

While the architecture uses advanced protocols (QUIC), the physical layer (Bluetooth LE) imposes severe constraints on real-time video performance.

### Bandwidth Bottleneck

- **BLE Throughput**: Real-world application throughput is typically **0.5 - 1.5 Mbps**.
- **Video Requirement**: Even moderate quality compressed video (480p/30fps) requires **2-5 Mbps**.
- **Result**: The pipe is too small for standard video.

### Real-World Performance

Consequently, the "streaming" experienced in the sample app is:

- **Resolution**: Very low (typically **320x240** to **480x360**).
- **Frame Rate**: Unstable, often dropping to **5-15 fps** despite configuration for higher rates.
- **Latency**: Significant buffering delay (often exceeding 1-2 seconds).
- **Artifacts**: Heavy compression artifacts or dropped frames due to congestion.

### Why "QUIC over BLE"?

The use of QUIC isn't for speed (BLE limits that), but for **reliability**:
- Handles packet loss better than raw GATT notifications.
- Prevents head-of-line blocking (audio doesn't stop if video drops).
- Manages congestion to keep the connection alive despite saturation.

---

## 3. Conclusion

The CameraAccess app demonstrates **connectivity**, not high-fidelity streaming. It proves the ability to establish a secure data tunnel to the glasses, but the video capability is a "preview" quality stream limited by the physics of Bluetooth Low Energy, not the app's implementation.
