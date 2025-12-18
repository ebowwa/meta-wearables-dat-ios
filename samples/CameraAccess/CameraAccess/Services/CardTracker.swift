/*
 * CardTracker.swift
 * CameraAccess
 *
 * Layer 2.5: Aggregation - Stabilizes and groups card detections
 * - Temporal voting to reduce flickering
 * - Object tracking with persistent IDs
 * - Hole card detection priority
 */

import Foundation
import CoreGraphics

/// Tracked card with stable identity across frames
struct TrackedCard: Identifiable {
    let id: UUID
    var position: CGRect
    var currentClass: String           // Most voted class
    var classHistory: [String]         // Last N predictions
    var confidence: Float              // Average confidence
    var framesSeen: Int
    var framesMissed: Int
    var isHoleCard: Bool               // Part of player's hand?
    
    /// Vote for most common class in history
    var votedClass: String {
        let counts = classHistory.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? currentClass
    }
    
    /// Stability score (0-1) based on class consistency
    var stability: Float {
        guard !classHistory.isEmpty else { return 0 }
        let votedCount = classHistory.filter { $0 == votedClass }.count
        return Float(votedCount) / Float(classHistory.count)
    }
}

/// Card tracking service for temporal stability
class CardTracker {
    
    // MARK: - Configuration
    
    /// Max history per tracked card
    private let historySize = 10
    
    /// Frames before removing missed card
    private let missedFrameThreshold = 5
    
    /// IoU threshold for matching detections to tracked cards
    private let matchingIoU: Float = 0.3
    
    /// Y position threshold for hole cards (bottom 40% of frame)
    private let holeCardYThreshold: CGFloat = 0.6
    
    /// Minimum stability to show a card
    private let minStability: Float = 0.5
    
    // MARK: - State
    
    private var trackedCards: [TrackedCard] = []
    private var lockedHoleCards: [TrackedCard] = []
    
    // MARK: - Public API
    
    /// Process new frame of detections, return stable cards
    func process(_ detections: [DetectedCard]) -> [DetectedCard] {
        // 1. Match new detections to existing tracked cards
        var matched = Set<UUID>()
        var unmatchedDetections: [DetectedCard] = []
        
        for detection in detections {
            if let matchIdx = findMatch(for: detection) {
                // Update existing tracked card
                updateTrackedCard(at: matchIdx, with: detection)
                matched.insert(trackedCards[matchIdx].id)
            } else {
                unmatchedDetections.append(detection)
            }
        }
        
        // 2. Create new tracked cards for unmatched detections
        for detection in unmatchedDetections {
            let isHole = detection.boundingBox.midY > holeCardYThreshold
            let newCard = TrackedCard(
                id: UUID(),
                position: detection.boundingBox,
                currentClass: detection.card.yoloLabel,
                classHistory: [detection.card.yoloLabel],
                confidence: detection.confidence,
                framesSeen: 1,
                framesMissed: 0,
                isHoleCard: isHole
            )
            trackedCards.append(newCard)
        }
        
        // 3. Increment missed count for unmatched tracked cards
        for i in trackedCards.indices {
            if !matched.contains(trackedCards[i].id) {
                trackedCards[i].framesMissed += 1
            }
        }
        
        // 4. Remove cards that have been missing too long
        trackedCards.removeAll { $0.framesMissed > missedFrameThreshold }
        
        // 5. Convert stable tracked cards to DetectedCard output
        return trackedCards
            .filter { $0.stability >= minStability }
            .compactMap { tracked -> DetectedCard? in
                guard let card = PokerCard.fromYOLOLabel(tracked.votedClass) else { return nil }
                return DetectedCard(
                    card: card,
                    confidence: tracked.confidence,
                    boundingBox: tracked.position
                )
            }
    }
    
    /// Get current hole cards (2 most stable cards in hole position)
    func getHoleCards() -> [DetectedCard] {
        return trackedCards
            .filter { $0.isHoleCard && $0.stability >= minStability }
            .sorted { $0.stability > $1.stability }
            .prefix(2)
            .compactMap { tracked -> DetectedCard? in
                guard let card = PokerCard.fromYOLOLabel(tracked.votedClass) else { return nil }
                return DetectedCard(
                    card: card,
                    confidence: tracked.confidence,
                    boundingBox: tracked.position
                )
            }
    }
    
    /// Reset tracking (new hand)
    func reset() {
        trackedCards.removeAll()
        lockedHoleCards.removeAll()
    }
    
    // MARK: - Private
    
    private func findMatch(for detection: DetectedCard) -> Int? {
        var bestMatch: Int?
        var bestIoU: Float = matchingIoU
        
        for (idx, tracked) in trackedCards.enumerated() {
            let iou = calculateIoU(detection.boundingBox, tracked.position)
            if iou > bestIoU {
                bestIoU = iou
                bestMatch = idx
            }
        }
        
        return bestMatch
    }
    
    private func updateTrackedCard(at index: Int, with detection: DetectedCard) {
        var card = trackedCards[index]
        
        // Update position (could lerp for smoothness)
        card.position = detection.boundingBox
        
        // Add to class history
        card.classHistory.append(detection.card.yoloLabel)
        if card.classHistory.count > historySize {
            card.classHistory.removeFirst()
        }
        
        // Update current class based on voting
        card.currentClass = card.votedClass
        
        // Update confidence (rolling average)
        card.confidence = 0.7 * card.confidence + 0.3 * detection.confidence
        
        // Increment seen, reset missed
        card.framesSeen += 1
        card.framesMissed = 0
        
        // Check hole card status
        card.isHoleCard = detection.boundingBox.midY > holeCardYThreshold
        
        trackedCards[index] = card
    }
    
    private func calculateIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        if intersection.isNull { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        
        return Float(intersectionArea / unionArea)
    }
}

// MARK: - PokerCard Extension

extension PokerCard {
    /// Convert to YOLO label format (e.g., "10H", "AS")
    var yoloLabel: String {
        let rankStr: String
        switch rank {
        case .ace: rankStr = "A"
        case .two: rankStr = "2"
        case .three: rankStr = "3"
        case .four: rankStr = "4"
        case .five: rankStr = "5"
        case .six: rankStr = "6"
        case .seven: rankStr = "7"
        case .eight: rankStr = "8"
        case .nine: rankStr = "9"
        case .ten: rankStr = "10"
        case .jack: rankStr = "J"
        case .queen: rankStr = "Q"
        case .king: rankStr = "K"
        }
        
        let suitStr: String
        switch suit {
        case .clubs: suitStr = "C"
        case .diamonds: suitStr = "D"
        case .hearts: suitStr = "H"
        case .spades: suitStr = "S"
        }
        
        return rankStr + suitStr
    }
}
