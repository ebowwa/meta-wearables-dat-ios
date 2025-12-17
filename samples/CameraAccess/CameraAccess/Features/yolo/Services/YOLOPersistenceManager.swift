/*
 * YOLOPersistenceManager.swift
 * CameraAccess
 *
 * Central manager for SwiftData persistence of YOLO models.
 * This is the database-first source of truth for all model data.
 */

import Foundation
import SwiftData

/// Manages the SwiftData database for YOLO models
@MainActor
final class YOLOPersistenceManager {
    
    // MARK: - Singleton
    
    static let shared = YOLOPersistenceManager()
    
    // MARK: - Properties
    
    private(set) var modelContainer: ModelContainer?
    private(set) var modelContext: ModelContext?
    
    /// Whether the database has been initialized
    private(set) var isInitialized = false
    
    // MARK: - Schema
    
    static let schema = Schema([
        ModelCatalog.self,
        UserPreferences.self,
        InterpreterConfigEntity.self,
        DetectionSessionEntity.self
    ])
    
    // MARK: - Init
    
    private init() {
        setupContainer()
    }
    
    private func setupContainer() {
        do {
            let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: Self.schema, configurations: config)
            modelContext = modelContainer?.mainContext
            isInitialized = true
            
            // Seed data on first launch
            Task {
                await seedIfNeeded()
            }
        } catch {
            print("❌ Failed to setup SwiftData container: \(error)")
            isInitialized = false
        }
    }
    
    // MARK: - Seed Data
    
    /// Seed the database with featured models on first launch
    func seedIfNeeded() async {
        guard let context = modelContext else { return }
        
        // Check if we have any models
        let descriptor = FetchDescriptor<ModelCatalog>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        
        guard existingCount == 0 else {
            print("📦 Database already has \(existingCount) models, skipping seed")
            return
        }
        
        print("🌱 Seeding database with featured models...")
        
        for modelInfo in FeaturedModels.all {
            let catalog = ModelCatalog(from: modelInfo, isSeeded: true)
            
            // Create associated preferences and config
            let prefs = UserPreferences(modelId: catalog.id)
            let config = InterpreterConfigEntity(modelId: catalog.id)
            
            catalog.userPreferences = prefs
            catalog.interpreterConfig = config
            
            context.insert(catalog)
        }
        
        try? context.save()
        print("✅ Seeded \(FeaturedModels.all.count) models")
    }
    
    // MARK: - Model Catalog CRUD
    
    /// Get all models from the catalog
    func allModels() -> [ModelCatalog] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<ModelCatalog>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Get a model by ID
    func model(withId id: String) -> ModelCatalog? {
        guard let context = modelContext else { return nil }
        let predicate = #Predicate<ModelCatalog> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try? context.fetch(descriptor).first
    }
    
    /// Add a new model to the catalog
    func addModel(_ info: YOLOModelInfo, isSeeded: Bool = false) -> ModelCatalog? {
        guard let context = modelContext else { return nil }
        
        // Check if already exists
        if let existing = model(withId: info.id) {
            return existing
        }
        
        let catalog = ModelCatalog(from: info, isSeeded: isSeeded)
        
        // Create associated entities
        let prefs = UserPreferences(modelId: catalog.id)
        let config = InterpreterConfigEntity(modelId: catalog.id)
        
        catalog.userPreferences = prefs
        catalog.interpreterConfig = config
        
        context.insert(catalog)
        try? context.save()
        
        return catalog
    }
    
    /// Delete a model from the catalog
    func deleteModel(_ model: ModelCatalog) {
        guard let context = modelContext else { return }
        context.delete(model)
        try? context.save()
    }
    
    /// Update local path for a downloaded model
    func setLocalPath(_ path: String, for modelId: String) {
        guard let model = model(withId: modelId) else { return }
        model.localPath = path
        try? modelContext?.save()
    }
    
    // MARK: - User Preferences
    
    /// Get favorites
    func favoriteModels() -> [ModelCatalog] {
        guard let context = modelContext else { return [] }
        let predicate = #Predicate<UserPreferences> { $0.isFavorite }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        guard let prefs = try? context.fetch(descriptor) else { return [] }
        return prefs.compactMap { $0.model }
    }
    
    /// Get recently used models
    func recentlyUsed(limit: Int = 5) -> [ModelCatalog] {
        guard let context = modelContext else { return [] }
        var descriptor = FetchDescriptor<UserPreferences>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        guard let prefs = try? context.fetch(descriptor) else { return [] }
        return prefs.compactMap { $0.model }
    }
    
    /// Toggle favorite for a model
    func toggleFavorite(for modelId: String) {
        guard let model = model(withId: modelId),
              let prefs = model.userPreferences else { return }
        prefs.toggleFavorite()
        try? modelContext?.save()
    }
    
    /// Record that a model was used
    func recordUsage(for modelId: String) {
        guard let model = model(withId: modelId),
              let prefs = model.userPreferences else { return }
        prefs.recordUsage()
        try? modelContext?.save()
    }
    
    // MARK: - Interpreter Config
    
    /// Get interpreter config for a model (creates default if needed)
    func interpreterConfig(for modelId: String) -> InterpreterConfigEntity? {
        guard let model = model(withId: modelId) else { return nil }
        
        if let existing = model.interpreterConfig {
            return existing
        }
        
        // Create default config
        let config = InterpreterConfigEntity(modelId: modelId)
        model.interpreterConfig = config
        try? modelContext?.save()
        return config
    }
    
    /// Update confidence threshold for a model
    func setConfidenceThreshold(_ threshold: Float, for modelId: String) {
        guard let config = interpreterConfig(for: modelId) else { return }
        config.confidenceThreshold = threshold
        try? modelContext?.save()
    }
    
    // MARK: - Detection Sessions
    
    /// Start a new detection session
    func startSession(for modelId: String) -> DetectionSessionEntity? {
        guard let context = modelContext,
              let model = model(withId: modelId) else { return nil }
        
        let session = DetectionSessionEntity(modelId: modelId, model: model)
        context.insert(session)
        return session
    }
    
    /// End a detection session
    func endSession(_ session: DetectionSessionEntity) {
        session.endSession()
        try? modelContext?.save()
    }
    
    /// Get sessions for a model
    func sessions(for modelId: String, limit: Int = 10) -> [DetectionSessionEntity] {
        guard let context = modelContext else { return [] }
        let predicate = #Predicate<DetectionSessionEntity> { $0.modelId == modelId }
        var descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Queries
    
    /// Get models by type
    func models(ofType type: YOLOModelType) -> [ModelCatalog] {
        guard let context = modelContext else { return [] }
        let typeRaw = type.rawValue
        let predicate = #Predicate<ModelCatalog> { $0.modelTypeRaw == typeRaw }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Get models by source type
    func models(fromSource sourceType: String) -> [ModelCatalog] {
        guard let context = modelContext else { return [] }
        let predicate = #Predicate<ModelCatalog> { $0.sourceType == sourceType }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Get downloaded (local) models only
    func downloadedModels() -> [ModelCatalog] {
        allModels().filter { $0.localPath != nil || $0.sourceType == "bundled" }
    }
    
    // MARK: - Save
    
    /// Save any pending changes
    func save() {
        try? modelContext?.save()
    }
    
    // MARK: - Debug
    
    /// Print database contents for debugging
    func debugPrint() {
        print("═══════════════════════════════════════")
        print("📊 YOLO Database Contents")
        print("═══════════════════════════════════════")
        
        let models = allModels()
        print("Models (\(models.count)):")
        for m in models {
            let fav = m.userPreferences?.isFavorite == true ? "⭐" : "  "
            let downloaded = m.localPath != nil || m.sourceType == "bundled" ? "✓" : "○"
            print("  \(fav) [\(downloaded)] \(m.id) (\(m.modelTypeRaw)) - \(m.sourceType)")
        }
        
        print("───────────────────────────────────────")
    }
    
    // MARK: - Cleanup
    
    /// Remove duplicate models from database
    /// This handles cases where:
    /// - A local discovered model duplicates a seeded remote model
    /// - Multiple entries exist for the same underlying model file
    func cleanupDuplicates() {
        guard let context = modelContext else { return }
        
        let models = allModels()
        var toDelete: [ModelCatalog] = []
        var seenIds: Set<String> = []
        
        for model in models {
            // For local_ prefixed models, check if the base name matches a featured model
            if model.id.hasPrefix("local_") {
                let baseName = String(model.id.dropFirst("local_".count))
                
                // Check if there's a featured model with this base name as ID
                if models.contains(where: { $0.id == baseName && $0.isSeeded }) {
                    print("🧹 Removing duplicate local model: \(model.id) (matches seeded \(baseName))")
                    toDelete.append(model)
                    continue
                }
            }
            
            // Generic duplicate detection - keep first occurrence
            if seenIds.contains(model.name) {
                print("🧹 Removing duplicate model by name: \(model.id)")
                toDelete.append(model)
            } else {
                seenIds.insert(model.name)
            }
        }
        
        for model in toDelete {
            context.delete(model)
        }
        
        if !toDelete.isEmpty {
            try? context.save()
            print("✅ Cleaned up \(toDelete.count) duplicate(s)")
        }
    }
}

// MARK: - Featured Models (Seed Data Source)

/// Featured models to seed on first launch
enum FeaturedModels {
    static let all: [YOLOModelInfo] = [
        YOLOModelInfo(
            id: "featured_yolo11_poker",
            name: "YOLO11 Poker Detection",
            description: "Detects 52 playing cards in real-time",
            source: .remote(url: "https://github.com/ebowwa/meta-wearables-dat-ios/releases/download/poker-model-v1.0/YOLO11PokerInt8LUT.mlpackage.zip"),
            version: "1.0",
            modelType: .poker,
            sizeBytes: 4_800_000
        )
    ]
}
