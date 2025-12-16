/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics

// MARK: - Race Category Model

/// Represents the 7 race/ethnicity categories from the FairFace dataset
/// These categories are designed to reduce bias through balanced representation
enum RaceCategory: String, CaseIterable, Identifiable {
    case white = "White"
    case black = "Black"
    case latinoHispanic = "Latino_Hispanic"
    case eastAsian = "East Asian"
    case southeastAsian = "Southeast Asian"
    case indian = "Indian"
    case middleEastern = "Middle Eastern"
    
    var id: String { rawValue }
    
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        case .latinoHispanic: return "Latino/Hispanic"
        case .eastAsian: return "East Asian"
        case .southeastAsian: return "Southeast Asian"
        case .indian: return "Indian"
        case .middleEastern: return "Middle Eastern"
        }
    }
    
    /// Emoji representation for UI
    var emoji: String {
        switch self {
        case .white: return "👤"
        case .black: return "👤"
        case .latinoHispanic: return "👤"
        case .eastAsian: return "👤"
        case .southeastAsian: return "👤"
        case .indian: return "👤"
        case .middleEastern: return "👤"
        }
    }
    
    /// Parse from YOLO model output label
    static func fromLabel(_ label: String) -> RaceCategory? {
        // The model outputs indices 0-6 corresponding to categories
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try direct match first
        if let category = RaceCategory(rawValue: trimmed) {
            return category
        }
        
        // Try case-insensitive match
        let lowercased = trimmed.lowercased()
        for category in RaceCategory.allCases {
            if category.rawValue.lowercased() == lowercased ||
               category.displayName.lowercased() == lowercased {
                return category
            }
        }
        
        // Handle specific variations
        switch lowercased {
        case "latino", "hispanic", "latino/hispanic", "latino_hispanic":
            return .latinoHispanic
        case "east asian", "east_asian", "eastasian":
            return .eastAsian
        case "southeast asian", "southeast_asian", "southeastasian":
            return .southeastAsian
        case "middle eastern", "middle_eastern", "middleeastern":
            return .middleEastern
        default:
            return nil
        }
    }
    
    /// Get category by index (0-6)
    static func fromIndex(_ index: Int) -> RaceCategory? {
        guard index >= 0 && index < allCases.count else { return nil }
        return allCases[index]
    }
}

// MARK: - Classification Result

/// A face classification result with category and confidence
struct ClassifiedFace: Identifiable {
    let id = UUID()
    let category: RaceCategory
    let confidence: Float
    let allConfidences: [RaceCategory: Float]
    
    /// Top 3 most likely categories
    var topCategories: [(RaceCategory, Float)] {
        allConfidences
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value) }
    }
}
