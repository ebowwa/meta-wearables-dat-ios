//
//  OnDeviceKNN.swift
//  CameraAccess
//
//  K-Nearest Neighbors classifier using embeddings for on-device learning
//  Ported from Python: live-camera-learning/python/edaxshifu/knn_classifier.py
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

/// Feedback history entry for tracking corrections
struct FeedbackEntry {
    let predicted: String
    let correct: String
    let source: String  // "user", "gemini", "manual"
    let timestamp: Date
}

/// On-device KNN classifier for few-shot learning
/// Matches Python AdaptiveKNNClassifier from knn_classifier.py
class OnDeviceKNN: ObservableObject {
    
    // MARK: - Configuration (matches Python __init__ params)
    let k: Int
    var confidenceThreshold: Float
    let maxSamplesPerClass: Int  // Memory management (Python line 39)
    
    // Embedding dimension - auto-detected from first sample
    // ResNet18 = 512-dim (Python reference), MobileNet = 1280-dim (fallback)
    private var embeddingDimension: Int?
    
    // MARK: - Training Data
    private var embeddings: [[Float]] = []
    private var labels: [String] = []
    
    // MARK: - Published State
    @Published var trainedClasses: [String] = []
    @Published var samplesPerClass: [String: Int] = [:]
    @Published var totalSamples: Int = 0
    
    // MARK: - Feedback Tracking (matches Python AdaptiveKNNClassifier)
    private var feedbackHistory: [FeedbackEntry] = []
    var autoSave: Bool = true
    let saveInterval: Int = 10  // Save after every N new samples (Python line 429)
    private var samplesSinceLastSave: Int = 0
    
    // MARK: - Thread Safety (matches Python self._lock = threading.RLock())
    private let lock = NSLock()
    
    // MARK: - Storage
    private let storageURL: URL
    
    init(k: Int = 3, confidenceThreshold: Float = 0.6, maxSamplesPerClass: Int = 100) {
        self.k = k
        self.confidenceThreshold = confidenceThreshold
        self.maxSamplesPerClass = maxSamplesPerClass
        
        // Setup storage path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = documentsPath.appendingPathComponent("knn_model.json")
        
        // Load existing model
        loadModel()
    }
    
    // MARK: - Training (matches Python add_sample lines 140-163)
    
    /// Add a training sample with memory management
    func addSample(embedding: [Float], label: String) {
        // Auto-detect embedding dimension from first sample
        if embeddingDimension == nil {
            embeddingDimension = embedding.count
            print("📐 Auto-detected embedding dimension: \(embedding.count)")
        }
        
        // Validate embedding dimension matches existing samples
        if embedding.count != embeddingDimension {
            print("❌ Embedding dimension mismatch: got \(embedding.count), expected \(embeddingDimension!)")
            print("   This can happen if the embedding model changed. Consider resetting the KNN model.")
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        embeddings.append(embedding)
        labels.append(label)
        
        // Memory management (Python lines 156-157)
        manageMemory()
        
        updateStats()
        print("📝 Added sample for '\(label)' (total: \(totalSamples))")
        
        // Auto-save if enabled (Python lines 456-457)
        samplesSinceLastSave += 1
        if autoSave && samplesSinceLastSave >= saveInterval {
            saveModel()
            samplesSinceLastSave = 0
        }
    }
    
    /// Add a feedback sample (correction) - matches Python add_feedback_sample lines 431-459
    func addFeedbackSample(embedding: [Float], predictedLabel: String, correctLabel: String, source: String = "user") {
        // Add the corrected sample
        addSample(embedding: embedding, label: correctLabel)
        
        // Track feedback
        let entry = FeedbackEntry(
            predicted: predictedLabel,
            correct: correctLabel,
            source: source,
            timestamp: Date()
        )
        feedbackHistory.append(entry)
        
        print("🔄 Learned from feedback: \(predictedLabel) → \(correctLabel) (via \(source))")
    }
    
    /// Memory management - limit samples per class (Python lines 165-187)
    private func manageMemory() {
        // Count samples per class
        var counts: [String: Int] = [:]
        for label in labels {
            counts[label, default: 0] += 1
        }
        
        // Prune oldest samples if over limit
        for (label, count) in counts where count > maxSamplesPerClass {
            let excessCount = count - maxSamplesPerClass
            var removed = 0
            
            // Remove oldest (first) samples for this class
            var i = 0
            while i < labels.count && removed < excessCount {
                if labels[i] == label {
                    labels.remove(at: i)
                    embeddings.remove(at: i)
                    removed += 1
                } else {
                    i += 1
                }
            }
            
            print("🗑️ Pruned \(removed) old samples for class '\(label)'")
        }
    }
    
    /// Remove all samples for a label
    func removeSamples(for label: String) {
        lock.lock()
        defer { lock.unlock() }
        
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
    
    /// Clear all training data (Python lines 405-411)
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        embeddings.removeAll()
        labels.removeAll()
        feedbackHistory.removeAll()
        updateStats()
        print("🗑️ KNN model reset")
    }
    
    // MARK: - Prediction (matches Python predict lines 259-330)
    
    func predict(embedding: [Float]) -> KNNResult {
        lock.lock()
        defer { lock.unlock() }
        
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
        
        // Sort by distance (ascending)
        distances.sort { $0.distance < $1.distance }
        
        // Take k nearest neighbors
        let kNearest = Array(distances.prefix(min(k, embeddings.count)))
        
        // Get neighbor labels and distances
        let neighborLabels = kNearest.map { labels[$0.index] }
        let neighborDistances = kNearest.map { $0.distance }
        
        // CRITICAL FIX: Check if nearest neighbor is actually similar enough
        // Cosine distance: 0 = identical, 1 = opposite, 0.5 = orthogonal
        // If nearest neighbor distance > 0.4, the embedding is too different to be a match
        let nearestDistance = neighborDistances.first ?? 1.0
        let isSimilarEnough = nearestDistance < 0.4
        
        // Convert cosine distance to similarity (line 294)
        let similarities = neighborDistances.map { 1.0 - $0 }
        
        // Calculate scores for each class (lines 296-306)
        let uniqueLabels = Array(Set(labels))
        var allScores: [String: Float] = [:]
        let totalSimilarity = similarities.reduce(0, +)
        
        for label in uniqueLabels {
            var labelSimilaritySum: Float = 0
            for (i, neighborLabel) in neighborLabels.enumerated() {
                if neighborLabel == label {
                    labelSimilaritySum += similarities[i]
                }
            }
            allScores[label] = totalSimilarity > 0 ? labelSimilaritySum / totalSimilarity : 0
        }
        
        // Get prediction and confidence
        var predLabel = "unknown"
        var confidence: Float = 0
        
        if let best = allScores.max(by: { $0.value < $1.value }) {
            predLabel = best.key
            confidence = best.value
            
            // Confidence adjustment (lines 313-316)
            // Scale confidence by how close the nearest neighbor actually is
            // Distance 0 → full confidence, Distance 0.4 → minimum confidence
            let distanceFactor = max(0, 1.0 - (nearestDistance / 0.4))
            confidence *= distanceFactor
        }
        
        // Determine if known based on:
        // 1. Confidence above threshold
        // 2. Nearest neighbor is actually similar (not just "closest of bad options")
        // 3. We have at least 2 different classes OR nearest distance is very close (< 0.2)
        let hasMultipleClasses = uniqueLabels.count >= 2
        let isVeryClose = nearestDistance < 0.2
        let isKnown = confidence >= confidenceThreshold && isSimilarEnough && (hasMultipleClasses || isVeryClose)
        
        var nearestNeighbors: [(label: String, distance: Float)] = []
        for neighbor in kNearest {
            nearestNeighbors.append((labels[neighbor.index], neighbor.distance))
        }
        
        // Add debug logging for predictions
        if isKnown {
            print("🎯 KNN: '\(predLabel)' (conf: \(String(format: "%.2f", confidence)), dist: \(String(format: "%.3f", nearestDistance)))")
        }
        
        return KNNResult(
            label: isKnown ? predLabel : "unknown",
            confidence: confidence,
            isKnown: isKnown,
            allScores: allScores,
            nearestNeighbors: nearestNeighbors
        )
    }
    
    // MARK: - Statistics (matches Python get_accuracy_stats lines 461-475)
    
    func getAccuracyStats() -> [String: Any] {
        guard !feedbackHistory.isEmpty else { return [:] }
        
        let total = feedbackHistory.count
        let correct = feedbackHistory.filter { $0.predicted == $0.correct }.count
        let uniqueCorrections = Set(feedbackHistory.map { $0.correct }).count
        
        return [
            "total_feedback": total,
            "correct_predictions": correct,
            "accuracy": total > 0 ? Float(correct) / Float(total) : 0,
            "unique_corrections": uniqueCorrections
        ]
    }
    
    /// Get known classes (Python line 332-336)
    func getKnownClasses() -> [String] {
        return trainedClasses
    }
    
    /// Get sample counts (Python lines 338-343)
    func getSampleCount() -> [String: Int] {
        return samplesPerClass
    }
    
    // MARK: - Distance Metrics
    
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        
        let similarity = dotProduct / (sqrt(normA) * sqrt(normB) + 1e-8)
        return 1.0 - similarity
    }
    
    // MARK: - Persistence (matches Python save_model/load_model)
    
    func saveModel() {
        lock.lock()
        defer { lock.unlock() }
        
        let data = KNNModelData(
            embeddings: embeddings,
            labels: labels,
            k: k,
            confidenceThreshold: confidenceThreshold,
            maxSamplesPerClass: maxSamplesPerClass,
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
    
    func loadModel() {
        lock.lock()
        defer { lock.unlock() }
        
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
    
    /// Update confidence threshold (Python line 413-416)
    func updateConfidenceThreshold(_ threshold: Float) {
        confidenceThreshold = threshold
        print("⚙️ Confidence threshold updated to \(threshold)")
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
    let maxSamplesPerClass: Int
    let savedAt: String
}

