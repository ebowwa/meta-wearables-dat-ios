/*
 * PokerHandInterpreter.swift
 * CameraAccess
 *
 * Interpreter for poker card detection models.
 * Parses card labels and analyzes poker hands.
 */

import Foundation

/// Represents a playing card
struct PokerCard: Hashable, Equatable {
    enum Suit: String, CaseIterable {
        case spades = "s"
        case hearts = "h"
        case diamonds = "d"
        case clubs = "c"
        
        var displayName: String {
            switch self {
            case .spades: return "♠"
            case .hearts: return "♥"
            case .diamonds: return "♦"
            case .clubs: return "♣"
            }
        }
    }
    
    enum Rank: Int, CaseIterable, Comparable {
        case two = 2, three, four, five, six, seven, eight, nine, ten
        case jack = 11, queen = 12, king = 13, ace = 14
        
        static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        var displayName: String {
            switch self {
            case .ace: return "A"
            case .king: return "K"
            case .queen: return "Q"
            case .jack: return "J"
            case .ten: return "10"
            default: return String(rawValue)
            }
        }
    }
    
    let rank: Rank
    let suit: Suit
    
    var displayName: String {
        "\(rank.displayName)\(suit.displayName)"
    }
    
    /// Parse card from YOLO label (e.g., "10c", "Ah", "Ks")
    static func fromLabel(_ label: String) -> PokerCard? {
        let label = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard label.count >= 2 else { return nil }
        
        // Extract suit (last character)
        guard let suitChar = label.last,
              let suit = Suit(rawValue: String(suitChar)) else {
            return nil
        }
        
        // Extract rank (everything before suit)
        let rankStr = String(label.dropLast())
        let rank: Rank?
        
        switch rankStr {
        case "a": rank = .ace
        case "k": rank = .king
        case "q": rank = .queen
        case "j": rank = .jack
        case "10": rank = .ten
        case "9": rank = .nine
        case "8": rank = .eight
        case "7": rank = .seven
        case "6": rank = .six
        case "5": rank = .five
        case "4": rank = .four
        case "3": rank = .three
        case "2": rank = .two
        default: rank = nil
        }
        
        guard let r = rank else { return nil }
        return PokerCard(rank: r, suit: suit)
    }
}

/// Poker hand rankings
enum PokerHandRank: Int, Comparable {
    case highCard = 1
    case pair = 2
    case twoPair = 3
    case threeOfAKind = 4
    case straight = 5
    case flush = 6
    case fullHouse = 7
    case fourOfAKind = 8
    case straightFlush = 9
    case royalFlush = 10
    
    static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var displayName: String {
        switch self {
        case .highCard: return "High Card"
        case .pair: return "Pair"
        case .twoPair: return "Two Pair"
        case .threeOfAKind: return "Three of a Kind"
        case .straight: return "Straight"
        case .flush: return "Flush"
        case .fullHouse: return "Full House"
        case .fourOfAKind: return "Four of a Kind"
        case .straightFlush: return "Straight Flush"
        case .royalFlush: return "Royal Flush"
        }
    }
}

/// Interpreter for poker card detection
final class PokerHandInterpreter: DetectionInterpreter {
    
    static let supportedModelTypes: Set<YOLOModelType> = [.poker]
    
    var displayName: String { "Poker Hand Analyzer" }
    
    func interpret(_ detections: [YOLODetection]) -> InterpretedDetections {
        // Parse cards from labels
        let cards = detections.compactMap { PokerCard.fromLabel($0.label) }
        let uniqueCards = Array(Set(cards))
        
        // Analyze hand
        let handRank = analyzeHand(uniqueCards)
        
        // Build summary
        let cardNames = uniqueCards.map { $0.displayName }.joined(separator: " ")
        let summary: String
        
        if uniqueCards.isEmpty {
            summary = "No cards detected"
        } else if uniqueCards.count < 5 {
            summary = "\(uniqueCards.count) card\(uniqueCards.count > 1 ? "s" : ""): \(cardNames)"
        } else {
            summary = "\(handRank.displayName): \(cardNames)"
        }
        
        return InterpretedDetections(
            rawDetections: detections,
            summary: summary,
            metadata: [
                "cards": uniqueCards.map { $0.displayName },
                "handRank": handRank.displayName,
                "cardCount": uniqueCards.count
            ],
            modelType: .poker
        )
    }
    
    // MARK: - Hand Analysis
    
    private func analyzeHand(_ cards: [PokerCard]) -> PokerHandRank {
        guard cards.count >= 5 else { return .highCard }
        
        // Take best 5 cards for analysis
        let hand = Array(cards.prefix(7))
        
        let isFlush = checkFlush(hand)
        let isStraight = checkStraight(hand)
        let rankCounts = countRanks(hand)
        
        // Check for royal flush
        if isFlush && isStraight {
            let ranks = hand.map { $0.rank.rawValue }.sorted()
            if ranks.contains(10) && ranks.contains(14) { // 10 to Ace
                return .royalFlush
            }
            return .straightFlush
        }
        
        // Check rank-based hands
        let counts = rankCounts.values.sorted(by: >)
        
        if counts.first == 4 { return .fourOfAKind }
        if counts.first == 3 && counts.dropFirst().first == 2 { return .fullHouse }
        if isFlush { return .flush }
        if isStraight { return .straight }
        if counts.first == 3 { return .threeOfAKind }
        if counts.first == 2 && counts.dropFirst().first == 2 { return .twoPair }
        if counts.first == 2 { return .pair }
        
        return .highCard
    }
    
    private func checkFlush(_ cards: [PokerCard]) -> Bool {
        var suitCounts: [PokerCard.Suit: Int] = [:]
        for card in cards {
            suitCounts[card.suit, default: 0] += 1
        }
        return suitCounts.values.contains { $0 >= 5 }
    }
    
    private func checkStraight(_ cards: [PokerCard]) -> Bool {
        let ranks = Set(cards.map { $0.rank.rawValue })
        guard ranks.count >= 5 else { return false }
        
        let sorted = ranks.sorted()
        var consecutive = 1
        
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i-1] + 1 {
                consecutive += 1
                if consecutive >= 5 { return true }
            } else {
                consecutive = 1
            }
        }
        
        // Check A-2-3-4-5 (wheel)
        if ranks.contains(14) && ranks.contains(2) && ranks.contains(3) && ranks.contains(4) && ranks.contains(5) {
            return true
        }
        
        return false
    }
    
    private func countRanks(_ cards: [PokerCard]) -> [PokerCard.Rank: Int] {
        var counts: [PokerCard.Rank: Int] = [:]
        for card in cards {
            counts[card.rank, default: 0] += 1
        }
        return counts
    }
}
