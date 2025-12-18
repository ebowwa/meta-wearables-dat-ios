//
//  OnDeviceKNN.swift
//  CameraAccess
//
//  K-Nearest Neighbors classifier using embeddings for on-device learning
//

import Foundation
import Accelerate

/// Result of KNN classification
struct KNNResult {
    let label: String
    let confidence: Float
    let isKnown: Bool
    let allScores: [String: Float]
    let nearestNeighbors: [(label: String, distance: Float)]
}

/// On-device KNN classifier for few-shot learning
class OnDeviceKNN: ObservableObject {
    
    // MARK: - Configuration
    let k: Int
    var confidenceThreshold: Float
    private let embeddingDimension = 1280
    
    // MARK: - Training Data
    private var embeddings: [[Float]] = []
    private var labels: [String] = []
    
    // MARK: - Published State
    @Published var trainedClasses: [String] = []
    @Published var samplesPerClass: [String: Int] = [:]
    @Published var totalSamples: Int = 0
    
    // MARK: - Storage
    private let storageURL: URL
    
    init(k: Int = 3, confidenceThreshold: Float = 0.6) {
        self.k = k
        self.confidenceThreshold = confidenceThreshold
        
        // Setup storage path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = documentsPath.appendingPathComponent("knn_model.json")
        
        // Load existing model
        loadModel()
    }
    
    // MARK: - Training
    
    /// Add a training sample
    func addSample(embedding: [Float], label: String) {
        guard embedding.count == embeddingDimension else {
            print("❌ Invalid embedding dimension: \(embedding.count), expected \(embeddingDimension)")
            return
        }
        
        embeddings.append(embedding)
        labels.append(label)
        
        updateStats()
        print("📝 Added sample for '\(label)' (total: \(totalSamples))")
    }
    
    /// Remove all samples for a label
    func removeSamples(for label: String) {
        let indicesToRemove = labels.enumerated()
            .filter { $0.element == label }
            .map { $0.offset }
            .reversed()
        
        for index in indicesToRemove {
            embeddings.remove(at: index)
            labels.remove(at: index)
        }
        
        updateStats()
        print("🗑️ Removed all samples for '\(label)'")
    }
    
    /// Clear all training data
    func reset() {
        embeddings.removeAll()
        labels.removeAll()
        updateStats()
        print("🗑️ KNN model reset")
    }
    
    // MARK: - Prediction
    
    /// Predict label for embedding
    func predict(embedding: [Float]) -> KNNResult {
        guard !embeddings.isEmpty else {
            return KNNResult(
                label: "unknown",
                confidence: 0,
                isKnown: false,
                allScores: [:],
                nearestNeighbors: []
            )
        }
        
        // Calculate distances to all training samples
        var distances: [(index: Int, distance: Float)] = []
        
        for (index, trainEmbedding) in embeddings.enumerated() {
            let distance = cosineDistance(embedding, trainEmbedding)
            distances.append((index, distance))
        }
        
        // Sort by distance (ascending - lower is more similar)
        distances.sort { $0.distance < $1.distance }
        
        // Take k nearest neighbors
        let kNearest = Array(distances.prefix(k))
        
        // Vote for label
        var votes: [String: Float] = [:]
        var nearestNeighbors: [(label: String, distance: Float)] = []
        
        for neighbor in kNearest {
            let label = labels[neighbor.index]
            // Weight vote by inverse distance (closer = higher weight)
            let weight = 1.0 / (neighbor.distance + 0.001)
            votes[label, default: 0] += weight
            nearestNeighbors.append((label, neighbor.distance))
        }
        
        // Normalize votes to get confidence
        let totalWeight = votes.values.reduce(0, +)
        var scores: [String: Float] = [:]
        for (label, weight) in votes {
            scores[label] = weight / totalWeight
        }
        
        // Get best label
        let bestLabel = scores.max { $0.value < $1.value }?.key ?? "unknown"
        let confidence = scores[bestLabel] ?? 0
        let isKnown = confidence >= confidenceThreshold
        
        return KNNResult(
            label: bestLabel,
            confidence: confidence,
            isKnown: isKnown,
            allScores: scores,
            nearestNeighbors: nearestNeighbors
        )
    }
    
    // MARK: - Distance Metrics
    
    /// Cosine distance (1 - cosine similarity)
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        // Use Accelerate for performance
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        let similarity = dotProduct / (sqrt(normA) * sqrt(normB) + 1e-8)
        return 1.0 - similarity
    }
    
    // MARK: - Persistence
    
    /// Save model to disk
    func saveModel() {
        let data = KNNModelData(
            embeddings: embeddings,
            labels: labels,
            k: k,
            confidenceThreshold: confidenceThreshold,
            savedAt: Date().ISO8601Format()
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: storageURL)
            print("💾 KNN model saved (\(totalSamples) samples, \(trainedClasses.count) classes)")
        } catch {
            print("❌ Failed to save KNN model: \(error)")
        }
    }
    
    /// Load model from disk
    func loadModel() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            print("📂 No existing KNN model found")
            return
        }
        
        do {
            let jsonData = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            let data = try decoder.decode(KNNModelData.self, from: jsonData)
            
            self.embeddings = data.embeddings
            self.labels = data.labels
            
            updateStats()
            print("📂 KNN model loaded (\(totalSamples) samples, \(trainedClasses.count) classes)")
            
        } catch {
            print("❌ Failed to load KNN model: \(error)")
        }
    }
    
    private func updateStats() {
        trainedClasses = Array(Set(labels)).sorted()
        totalSamples = labels.count
        
        samplesPerClass = [:]
        for label in labels {
            samplesPerClass[label, default: 0] += 1
        }
    }
}

// MARK: - Persistence Model

private struct KNNModelData: Codable {
    let embeddings: [[Float]]
    let labels: [String]
    let k: Int
    let confidenceThreshold: Float
    let savedAt: String
}
