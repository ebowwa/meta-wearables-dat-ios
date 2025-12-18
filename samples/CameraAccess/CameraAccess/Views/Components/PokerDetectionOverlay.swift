/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

// MARK: - Main Overlay

/// Minimalist poker detection overlay - Apple design philosophy
/// "Simple can be harder than complex" - Steve Jobs
struct PokerDetectionOverlay: View {
    let detectedCards: [DetectedCard]
    let handResult: PokerHandResult?
    let frameSize: CGSize
    let imageSize: CGSize?
    
    @State private var showCardList = false
    
    var body: some View {
        ZStack {
            // Subtle card indicators (not ugly bounding boxes)
            ForEach(detectedCards) { card in
                CardGlow(
                    card: card,
                    frameSize: frameSize,
                    imageSize: imageSize
                )
            }
            
            // The one thing that matters: your hand
            VStack {
                if let result = handResult, !detectedCards.isEmpty {
                    HandResultCard(
                        result: result,
                        cards: detectedCards,
                        showDetails: $showCardList
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            showCardList.toggle()
                        }
                    }
                }
                Spacer()
            }
            .padding(.top, 50)
        }
    }
}

// MARK: - Subtle Card Indicator

/// Card detection indicator with visible label
struct CardGlow: View {
    let card: DetectedCard
    let frameSize: CGSize
    let imageSize: CGSize?
    
    private var boxColor: Color {
        switch card.card.suit {
        case .hearts, .diamonds: return .red
        case .clubs, .spades: return .white
        }
    }
    
    var body: some View {
        let rect = card.boundingBoxForView(size: frameSize, imageSize: imageSize)
        
        // Card name label - positioned at the box location
        Text(card.card.displayName)
            .font(.system(size: 32, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(boxColor)
                    .shadow(color: .black, radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white, lineWidth: 2)
            )
            .position(x: rect.midX, y: rect.minY - 30)
    }
}




// MARK: - Hand Result Card

/// The hero element - clean, confident, beautiful
struct HandResultCard: View {
    let result: PokerHandResult
    let cards: [DetectedCard]
    @Binding var showDetails: Bool
    
    private var cardIcons: String {
        cards.prefix(5).map { $0.card.displayName }.joined(separator: " ")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main result
            HStack(spacing: 12) {
                Text(result.rank.emoji)
                    .font(.system(size: 28))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.rank.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(result.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                }
                
                Spacer()
                
                // Expand indicator
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Expandable card list
            if showDetails {
                Divider()
                    .background(Color.white.opacity(0.2))
                
                HStack(spacing: 8) {
                    ForEach(cards.prefix(7)) { card in
                        CardChip(card: card)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(handColor.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
    
    private var handColor: Color {
        switch result.rank {
        case .royalFlush, .straightFlush: return .purple
        case .fourOfAKind, .fullHouse: return .orange
        case .flush, .straight: return .blue
        case .threeOfAKind, .twoPair: return .green
        case .pair: return .teal
        case .highCard: return .gray
        }
    }
}

// MARK: - Card Chip

/// Small, elegant card indicator
struct CardChip: View {
    let card: DetectedCard
    
    private var chipColor: Color {
        switch card.card.suit {
        case .hearts, .diamonds: return .red
        case .clubs, .spades: return .primary
        }
    }
    
    var body: some View {
        Text(card.card.displayName)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(chipColor.opacity(0.8))
            )
    }
}

// MARK: - Toggle Button

/// Clean toggle for poker mode
struct PokerModeToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3)) {
                isEnabled.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .shadow(color: isEnabled ? .green.opacity(0.4) : .clear, radius: 8)
                
                Text("🃏")
                    .font(.system(size: 20))
            }
        }
        .accessibilityLabel(isEnabled ? "Disable poker detection" : "Enable poker detection")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        PokerDetectionOverlay(
            detectedCards: [
                DetectedCard(
                    card: PokerCard(suit: .hearts, rank: .ace),
                    confidence: 0.95,
                    boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.12, height: 0.2)
                ),
                DetectedCard(
                    card: PokerCard(suit: .diamonds, rank: .ace),
                    confidence: 0.88,
                    boundingBox: CGRect(x: 0.3, y: 0.35, width: 0.12, height: 0.2)
                ),
                DetectedCard(
                    card: PokerCard(suit: .spades, rank: .king),
                    confidence: 0.82,
                    boundingBox: CGRect(x: 0.5, y: 0.32, width: 0.12, height: 0.2)
                )
            ],
            handResult: PokerHandResult(
                rank: .pair,
                cards: [PokerCard(suit: .hearts, rank: .ace), PokerCard(suit: .diamonds, rank: .ace)],
                description: "Pair of Aces"
            ),
            frameSize: CGSize(width: 393, height: 852),
            imageSize: CGSize(width: 640, height: 480)
        )
    }
}
