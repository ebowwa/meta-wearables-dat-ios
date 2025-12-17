/*
 * YOLOPersistenceManager.swift
 * CameraAccess
 *
 * Manages SwiftData persistence for YOLO models,
 * including CRUD operations and usage tracking.
 */

import Foundation
import SwiftData

/// Manages persistence for YOLO model data
@MainActor
final class YOLOPersistenceManager {
    
    // MARK: - Singleton
    
    static let shared = YOLOPersistenceManager()
    
    // MARK: - Properties
    
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?
    
    // MARK: - Schema
    
    static let schema = Schema([
        YOLOModelRecord.self,
        DetectionSession.self,
        InterpreterConfig.self
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
        } catch {
            print("Failed to setup SwiftData container: \(error)")
        }
    }
    
    // MARK: - Model Record CRUD
    
    /// Get or create a record for a model
    func getOrCreateRecord(for model: YOLOModelInfo) -> YOLOModelRecord? {
        guard let context = modelContext else { return nil }
        
        // Try to find existing
        let id = model.id
        let predicate = #Predicate<YOLOModelRecord> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        // Create new
        let record = YOLOModelRecord(from: model)
        context.insert(record)
        try? context.save()
        return record
    }
    
    /// Get all model records
    func allRecords() -> [YOLOModelRecord] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<YOLOModelRecord>(sortBy: [SortDescriptor(\.lastUsedDate, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Get favorite models
    func favorites() -> [YOLOModelRecord] {
        guard let context = modelContext else { return [] }
        let predicate = #Predicate<YOLOModelRecord> { $0.isFavorite }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Get recently used models
    func recentlyUsed(limit: Int = 5) -> [YOLOModelRecord] {
        guard let context = modelContext else { return [] }
        var descriptor = FetchDescriptor<YOLOModelRecord>(sortBy: [SortDescriptor(\.lastUsedDate, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Toggle favorite status
    func toggleFavorite(for modelId: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<YOLOModelRecord> { $0.id == modelId }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        if let record = try? context.fetch(descriptor).first {
            record.isFavorite.toggle()
            try? context.save()
        }
    }
    
    /// Update confidence threshold for a model
    func setConfidenceThreshold(_ threshold: Float, for modelId: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<YOLOModelRecord> { $0.id == modelId }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        if let record = try? context.fetch(descriptor).first {
            record.confidenceThreshold = threshold
            try? context.save()
        }
    }
    
    // MARK: - Usage Tracking
    
    /// Record that a model was used
    func recordModelUsage(for modelId: String) {
        guard let context = modelContext else { return }
        let predicate = #Predicate<YOLOModelRecord> { $0.id == modelId }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        if let record = try? context.fetch(descriptor).first {
            record.lastUsedDate = Date()
            record.usageCount += 1
            try? context.save()
        }
    }
    
    // MARK: - Detection Sessions
    
    /// Start a new detection session
    func startSession(modelId: String) -> DetectionSession? {
        guard let context = modelContext else { return nil }
        
        // Find model record
        let predicate = #Predicate<YOLOModelRecord> { $0.id == modelId }
        let descriptor = FetchDescriptor(predicate: predicate)
        let model = try? context.fetch(descriptor).first
        
        let session = DetectionSession(model: model)
        context.insert(session)
        return session
    }
    
    /// End a detection session
    func endSession(_ session: DetectionSession) {
        session.endSession()
        try? modelContext?.save()
    }
    
    // MARK: - Interpreter Config
    
    /// Get or create interpreter config for a model
    func getOrCreateConfig(for modelId: String) -> InterpreterConfig? {
        guard let context = modelContext else { return nil }
        
        let predicate = #Predicate<InterpreterConfig> { $0.modelId == modelId }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        
        let config = InterpreterConfig(modelId: modelId)
        context.insert(config)
        try? context.save()
        return config
    }
    
    // MARK: - Save
    
    /// Save any pending changes
    func save() {
        try? modelContext?.save()
    }
}
