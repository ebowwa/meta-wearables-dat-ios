import Foundation

/// Analyzes a set of poker cards to determine hand strength
class PokerHandAnalyzer {
    
    static let shared = PokerHandAnalyzer()
    private init() {}
    
    /// Analyze detected cards and return the best hand ranking
    func analyzeHand(_ detectedCards: [DetectedCard]) -> PokerHandResult {
        // Remove duplicates (same card detected multiple times)
        let uniqueCards = removeDuplicates(detectedCards)
        
        guard !uniqueCards.isEmpty else {
            return PokerHandResult(rank: .highCard, cards: [], description: "No cards detected")
        }
        
        let cards = uniqueCards.map { $0.card }
        
        // Need at least 2 cards for meaningful analysis
        guard cards.count >= 2 else {
            let card = cards.first!
            return PokerHandResult(
                rank: .highCard,
                cards: [card],
                description: "Single card: \(card.displayName)"
            )
        }
        
        // Evaluate hand (check from highest to lowest)
        if let result = checkRoyalFlush(cards) { return result }
        if let result = checkStraightFlush(cards) { return result }
        if let result = checkFourOfAKind(cards) { return result }
        if let result = checkFullHouse(cards) { return result }
        if let result = checkFlush(cards) { return result }
        if let result = checkStraight(cards) { return result }
        if let result = checkThreeOfAKind(cards) { return result }
        if let result = checkTwoPair(cards) { return result }
        if let result = checkPair(cards) { return result }
        
        // High card
        let highCard = cards.max(by: { $0.rank < $1.rank })!
        return PokerHandResult(
            rank: .highCard,
            cards: [highCard],
            description: "High Card: \(highCard.displayName)"
        )
    }
    
    // MARK: - Hand Checks
    
    private func checkRoyalFlush(_ cards: [PokerCard]) -> PokerHandResult? {
        guard cards.count >= 5 else { return nil }
        
        for suit in PokerCard.Suit.allCases {
            let suitCards = cards.filter { $0.suit == suit }
            let ranks = Set(suitCards.map { $0.rank.rawValue })
            
            // Royal flush: A, K, Q, J, 10 of same suit
            if ranks.contains(1) && ranks.contains(10) && ranks.contains(11) &&
               ranks.contains(12) && ranks.contains(13) {
                let royalCards = suitCards.filter { [1, 10, 11, 12, 13].contains($0.rank.rawValue) }
                return PokerHandResult(
                    rank: .royalFlush,
                    cards: royalCards,
                    description: "Royal Flush! \(suit.rawValue)"
                )
            }
        }
        return nil
    }
    
    private func checkStraightFlush(_ cards: [PokerCard]) -> PokerHandResult? {
        guard cards.count >= 5 else { return nil }
        
        for suit in PokerCard.Suit.allCases {
            let suitCards = cards.filter { $0.suit == suit }.sorted { $0.rank < $1.rank }
            if let straightCards = findStraight(suitCards) {
                return PokerHandResult(
                    rank: .straightFlush,
                    cards: straightCards,
                    description: "Straight Flush: \(straightCards.map { $0.displayName }.joined(separator: " "))"
                )
            }
        }
        return nil
    }
    
    private func checkFourOfAKind(_ cards: [PokerCard]) -> PokerHandResult? {
        let rankGroups = Dictionary(grouping: cards) { $0.rank }
        if let fourKind = rankGroups.first(where: { $0.value.count >= 4 }) {
            return PokerHandResult(
                rank: .fourOfAKind,
                cards: Array(fourKind.value.prefix(4)),
                description: "Four of a Kind: \(fourKind.key.symbol)s"
            )
        }
        return nil
    }
    
    private func checkFullHouse(_ cards: [PokerCard]) -> PokerHandResult? {
        let rankGroups = Dictionary(grouping: cards) { $0.rank }
        let threes = rankGroups.filter { $0.value.count >= 3 }
        let pairs = rankGroups.filter { $0.value.count >= 2 }
        
        if let three = threes.first, pairs.count >= 2 {
            let pair = pairs.first { $0.key != three.key }
            if let p = pair {
                let fullHouseCards = Array(three.value.prefix(3)) + Array(p.value.prefix(2))
                return PokerHandResult(
                    rank: .fullHouse,
                    cards: fullHouseCards,
                    description: "Full House: \(three.key.symbol)s full of \(p.key.symbol)s"
                )
            }
        }
        return nil
    }
    
    private func checkFlush(_ cards: [PokerCard]) -> PokerHandResult? {
        guard cards.count >= 5 else { return nil }
        
        let suitGroups = Dictionary(grouping: cards) { $0.suit }
        if let flush = suitGroups.first(where: { $0.value.count >= 5 }) {
            let flushCards = Array(flush.value.sorted { $0.rank > $1.rank }.prefix(5))
            return PokerHandResult(
                rank: .flush,
                cards: flushCards,
                description: "Flush: \(flush.key.rawValue)"
            )
        }
        return nil
    }
    
    private func checkStraight(_ cards: [PokerCard]) -> PokerHandResult? {
        guard cards.count >= 5 else { return nil }
        
        let sorted = cards.sorted { $0.rank < $1.rank }
        if let straightCards = findStraight(sorted) {
            return PokerHandResult(
                rank: .straight,
                cards: straightCards,
                description: "Straight: \(straightCards.first!.displayName) to \(straightCards.last!.displayName)"
            )
        }
        return nil
    }
    
    private func checkThreeOfAKind(_ cards: [PokerCard]) -> PokerHandResult? {
        let rankGroups = Dictionary(grouping: cards) { $0.rank }
        if let threeKind = rankGroups.first(where: { $0.value.count >= 3 }) {
            return PokerHandResult(
                rank: .threeOfAKind,
                cards: Array(threeKind.value.prefix(3)),
                description: "Three of a Kind: \(threeKind.key.symbol)s"
            )
        }
        return nil
    }
    
    private func checkTwoPair(_ cards: [PokerCard]) -> PokerHandResult? {
        let rankGroups = Dictionary(grouping: cards) { $0.rank }
        let pairs = rankGroups.filter { $0.value.count >= 2 }.sorted { $0.key > $1.key }
        
        if pairs.count >= 2 {
            let twoPairCards = Array(pairs[0].value.prefix(2)) + Array(pairs[1].value.prefix(2))
            return PokerHandResult(
                rank: .twoPair,
                cards: twoPairCards,
                description: "Two Pair: \(pairs[0].key.symbol)s and \(pairs[1].key.symbol)s"
            )
        }
        return nil
    }
    
    private func checkPair(_ cards: [PokerCard]) -> PokerHandResult? {
        let rankGroups = Dictionary(grouping: cards) { $0.rank }
        if let pair = rankGroups.first(where: { $0.value.count >= 2 }) {
            return PokerHandResult(
                rank: .pair,
                cards: Array(pair.value.prefix(2)),
                description: "Pair: \(pair.key.symbol)s"
            )
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private func findStraight(_ sortedCards: [PokerCard]) -> [PokerCard]? {
        guard sortedCards.count >= 5 else { return nil }
        
        var consecutive: [PokerCard] = [sortedCards[0]]
        
        for i in 1..<sortedCards.count {
            let prev = consecutive.last!
            let current = sortedCards[i]
            
            if current.rank.rawValue == prev.rank.rawValue + 1 {
                consecutive.append(current)
                if consecutive.count >= 5 {
                    return consecutive
                }
            } else if current.rank.rawValue != prev.rank.rawValue {
                consecutive = [current]
            }
        }
        
        // Check for wheel (A-2-3-4-5)
        let ranks = Set(sortedCards.map { $0.rank.rawValue })
        if ranks.contains(1) && ranks.contains(2) && ranks.contains(3) &&
           ranks.contains(4) && ranks.contains(5) {
            return sortedCards.filter { [1, 2, 3, 4, 5].contains($0.rank.rawValue) }
        }
        
        return nil
    }
    
    private func removeDuplicates(_ detectedCards: [DetectedCard]) -> [DetectedCard] {
        var seen: Set<PokerCard> = []
        return detectedCards
            .sorted { $0.confidence > $1.confidence }  // Keep highest confidence
            .filter { seen.insert($0.card).inserted }
    }
}

// MARK: - Result Struct

struct PokerHandResult {
    let rank: PokerHandRank
    let cards: [PokerCard]
    let description: String
}
