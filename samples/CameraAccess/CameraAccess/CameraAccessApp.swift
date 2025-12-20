/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CameraAccessApp.swift
//
// Main entry point for the CameraAccess sample app demonstrating the Meta Wearables DAT SDK.
// This app shows how to connect to wearable devices (like Ray-Ban Meta smart glasses),
// stream live video from their cameras, and capture photos. It provides a complete example
// of DAT SDK integration including device registration, permissions, and media streaming.
//
// Additionally, this app runs an ASG Camera Server (HTTP on port 8089) that exposes
// the glasses camera to other devices on the local network.
//

import Foundation
import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@main
struct CameraAccessApp: App {
  #if DEBUG
  // Debug menu for simulating device connections during development
  @StateObject private var debugMenuViewModel = DebugMenuViewModel(mockDeviceKit: MockDeviceKit.shared)
  #endif
  private let wearables: WearablesInterface
  @StateObject private var wearablesViewModel: WearablesViewModel
  
  /// Delegate for handling remote camera requests from the ASG Camera Server
  private let serverDelegate = CameraServerDelegate()

  init() {
    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[CameraAccess] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    let wearables = Wearables.shared
    self.wearables = wearables
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
    
    // Start the ASG Camera Server for external access
    // Other devices can access the camera at http://[device-ip]:8089
    startCameraServer()
  }
  
  /// Start the ASG Camera Server
  private func startCameraServer() {
    let config = ServerConfig(
      port: 8089,
      serverName: "Meta Glasses Camera Server",
      corsEnabled: true
    )
    ASGServerManager.shared.configure(with: config)
    
    if ASGServerManager.shared.startServer(delegate: serverDelegate) {
      if let serverURL = ASGServerManager.shared.serverURL {
        NSLog("[CameraAccess] 🌐 ASG Camera Server started at: \(serverURL)")
      }
    } else {
      NSLog("[CameraAccess] ❌ Failed to start ASG Camera Server")
    }
  }

  var body: some Scene {
    WindowGroup {
      // Main app view with access to the shared Wearables SDK instance
      // The Wearables.shared singleton provides the core DAT API
      MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
        // Show error alerts for view model failures
        .alert("Error", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }
        // Show server URL in a subtle banner
        .overlay(alignment: .bottom) {
          if let serverURL = ASGServerManager.shared.serverURL {
            Text("📡 \(serverURL)")
              .font(.caption)
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(.ultraThinMaterial)
              .cornerRadius(8)
              .padding(.bottom, 50)
          }
        }
        #if DEBUG
      .sheet(isPresented: $debugMenuViewModel.showDebugMenu) {
        MockDeviceKitView(viewModel: debugMenuViewModel.mockDeviceKitViewModel)
      }
      .overlay {
        DebugMenuView(debugMenuViewModel: debugMenuViewModel)
      }
        #endif

      // Registration view handles the flow for connecting to the glasses via Meta AI
      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}

// MARK: - Camera Server Delegate

/// Handles remote camera requests from the ASG Camera Server
/// When users access the web interface and click "Take Photo", this delegate is notified
class CameraServerDelegate: ASGCameraServerDelegate {
  func cameraServerDidRequestCapture(_ server: ASGCameraServer) {
    NSLog("[CameraAccess] 📸 Remote capture requested via HTTP")
    // Note: The actual capture would be triggered through the StreamSessionViewModel
    // For now, we just log the request - integration with the active streaming session
    // would require passing a reference to the view model
  }
  
  func cameraServerDidRequestStartRecording(_ server: ASGCameraServer) {
    NSLog("[CameraAccess] 🎥 Remote start recording requested via HTTP")
  }
  
  func cameraServerDidRequestStopRecording(_ server: ASGCameraServer) {
    NSLog("[CameraAccess] 🛑 Remote stop recording requested via HTTP")
  }
}
