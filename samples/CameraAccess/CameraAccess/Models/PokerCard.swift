/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import CoreGraphics

// MARK: - Poker Card Model

/// Represents a standard playing card with suit and rank
struct PokerCard: Hashable, Identifiable {
    var id: String { "\(rank.rawValue)\(suit.rawValue)" }
    
    enum Suit: String, CaseIterable {
        case hearts = "♥"
        case diamonds = "♦"
        case clubs = "♣"
        case spades = "♠"
        
        var color: String {
            switch self {
            case .hearts, .diamonds: return "red"
            case .clubs, .spades: return "black"
            }
        }
    }
    
    enum Rank: Int, CaseIterable, Comparable {
        case ace = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5
        case six = 6
        case seven = 7
        case eight = 8
        case nine = 9
        case ten = 10
        case jack = 11
        case queen = 12
        case king = 13
        
        var symbol: String {
            switch self {
            case .ace: return "A"
            case .jack: return "J"
            case .queen: return "Q"
            case .king: return "K"
            default: return String(rawValue)
            }
        }
        
        static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    let suit: Suit
    let rank: Rank
    
    var displayName: String {
        "\(rank.symbol)\(suit.rawValue)"
    }
    
    /// Parse card from YOLO11 class label (e.g., "10c", "Ah", "Ks")
    static func fromYOLOLabel(_ label: String) -> PokerCard? {
        guard label.count >= 2 else { return nil }
        
        let rankPart: String
        let suitChar: Character
        
        // Handle "10" rank (two characters)
        if label.hasPrefix("10") {
            rankPart = "10"
            suitChar = label.dropFirst(2).first ?? " "
        } else {
            rankPart = String(label.first!)
            suitChar = label.dropFirst().first ?? " "
        }
        
        let rank: Rank?
        switch rankPart.lowercased() {
        case "a": rank = .ace
        case "2": rank = .two
        case "3": rank = .three
        case "4": rank = .four
        case "5": rank = .five
        case "6": rank = .six
        case "7": rank = .seven
        case "8": rank = .eight
        case "9": rank = .nine
        case "10": rank = .ten
        case "j": rank = .jack
        case "q": rank = .queen
        case "k": rank = .king
        default: rank = nil
        }
        
        let suit: Suit?
        switch suitChar.lowercased() {
        case "h": suit = .hearts
        case "d": suit = .diamonds
        case "c": suit = .clubs
        case "s": suit = .spades
        default: suit = nil
        }
        
        guard let r = rank, let s = suit else { return nil }
        return PokerCard(suit: s, rank: r)
    }
}

// MARK: - Detected Card

/// A card detected by the YOLO11 model with confidence and position
struct DetectedCard: Identifiable {
    let id = UUID()
    let card: PokerCard
    let confidence: Float
    let boundingBox: CGRect  // Normalized coordinates (0-1)
    
    /// Convert bounding box to view coordinates
    func boundingBoxForView(size: CGSize) -> CGRect {
        CGRect(
            x: boundingBox.origin.x * size.width,
            y: boundingBox.origin.y * size.height,
            width: boundingBox.width * size.width,
            height: boundingBox.height * size.height
        )
    }
}

// MARK: - Poker Hand Ranking

/// Standard poker hand rankings from lowest to highest
enum PokerHandRank: Int, Comparable, CaseIterable {
    case highCard = 0
    case pair = 1
    case twoPair = 2
    case threeOfAKind = 3
    case straight = 4
    case flush = 5
    case fullHouse = 6
    case fourOfAKind = 7
    case straightFlush = 8
    case royalFlush = 9
    
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
    
    var emoji: String {
        switch self {
        case .highCard: return "🃏"
        case .pair: return "👯"
        case .twoPair: return "👯‍♀️"
        case .threeOfAKind: return "🎰"
        case .straight: return "📏"
        case .flush: return "🌊"
        case .fullHouse: return "🏠"
        case .fourOfAKind: return "🎲"
        case .straightFlush: return "⚡️"
        case .royalFlush: return "👑"
        }
    }
    
    static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
