/*
 * UserPreferences.swift
 * CameraAccess
 *
 * SwiftData entity for user-specific model preferences.
 * Separated from ModelCatalog so preferences can be reset without affecting catalog.
 */

import Foundation
import SwiftData

/// User preferences for a specific model
@Model
final class UserPreferences {
    // MARK: - Identity (references ModelCatalog)
    
    @Attribute(.unique) var modelId: String
    
    // MARK: - Preferences
    
    var isFavorite: Bool = false
    var isHidden: Bool = false
    
    // MARK: - Usage Statistics
    
    var usageCount: Int = 0
    var lastUsedAt: Date?
    
    // MARK: - Relationship
    
    var model: ModelCatalog?
    
    // MARK: - Init
    
    init(modelId: String) {
        self.modelId = modelId
    }
    
    // MARK: - Actions
    
    /// Record that this model was used
    func recordUsage() {
        usageCount += 1
        lastUsedAt = Date()
    }
    
    /// Toggle favorite status
    func toggleFavorite() {
        isFavorite.toggle()
    }
}
