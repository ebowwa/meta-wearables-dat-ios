/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// DetectedObject.swift
//
// Model representing an object detected by YOLO in a video frame.
//

import Foundation
import CoreGraphics

/// Represents a detected object from YOLOv3
struct DetectedObject: Identifiable {
    let id = UUID()
    
    /// Object class label (e.g. "person", "car", "dog")
    let label: String
    
    /// Detection confidence (0.0 - 1.0)
    let confidence: Float
    
    /// Bounding box in normalized coordinates (0.0 - 1.0)
    /// Origin is bottom-left in Vision framework
    let boundingBox: CGRect
    
    /// Convert Vision coordinates to UIKit coordinates
    func boundingBoxForView(size: CGSize) -> CGRect {
        // Vision uses bottom-left origin, convert to top-left
        let x = boundingBox.origin.x * size.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * size.height
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
