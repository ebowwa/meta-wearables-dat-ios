/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// Overlay view that displays detected poker cards with bounding boxes
struct PokerDetectionOverlay: View {
    let detectedCards: [DetectedCard]
    let handResult: PokerHandResult?
    let frameSize: CGSize
    
    var body: some View {
        ZStack {
            // Draw bounding boxes for each detected card
            ForEach(detectedCards) { card in
                CardBoundingBox(
                    card: card,
                    frameSize: frameSize
                )
            }
            
            // Hand strength indicator at top
            if let result = handResult, !detectedCards.isEmpty {
                VStack {
                    HandStrengthBadge(result: result)
                    Spacer()
                }
                .padding(.top, 60)
            }
        }
    }
}

/// Bounding box overlay for a single detected card
struct CardBoundingBox: View {
    let card: DetectedCard
    let frameSize: CGSize
    
    private var boxColor: Color {
        switch card.card.suit {
        case .hearts, .diamonds: return .red
        case .clubs, .spades: return .white
        }
    }
    
    var body: some View {
        let rect = card.boundingBoxForView(size: frameSize)
        
        ZStack(alignment: .topLeading) {
            // Bounding box rectangle
            Rectangle()
                .stroke(boxColor, lineWidth: 2)
                .background(boxColor.opacity(0.1))
            
            // Card label
            Text(card.card.displayName)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(boxColor.opacity(0.8))
                .cornerRadius(4)
                .offset(x: 2, y: -20)
            
            // Confidence badge
            Text("\(Int(card.confidence * 100))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.6))
                .cornerRadius(3)
                .offset(x: rect.width - 30, y: -18)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

/// Badge showing current hand strength
struct HandStrengthBadge: View {
    let result: PokerHandResult
    
    private var backgroundColor: Color {
        switch result.rank {
        case .royalFlush, .straightFlush: return .purple
        case .fourOfAKind, .fullHouse: return .orange
        case .flush, .straight: return .blue
        case .threeOfAKind, .twoPair: return .green
        case .pair: return .teal
        case .highCard: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(result.rank.emoji)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.rank.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Text(result.description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(backgroundColor.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        )
    }
}

/// Toggle button for poker detection mode
struct PokerModeToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 44, height: 44)
                
                Text("🃏")
                    .font(.system(size: 20))
            }
        }
        .accessibilityLabel(isEnabled ? "Disable poker detection" : "Enable poker detection")
    }
}

#Preview {
    ZStack {
        Color.black
        
        PokerDetectionOverlay(
            detectedCards: [
                DetectedCard(
                    card: PokerCard(suit: .hearts, rank: .ace),
                    confidence: 0.95,
                    boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.15, height: 0.25)
                ),
                DetectedCard(
                    card: PokerCard(suit: .spades, rank: .king),
                    confidence: 0.88,
                    boundingBox: CGRect(x: 0.4, y: 0.25, width: 0.15, height: 0.25)
                )
            ],
            handResult: PokerHandResult(
                rank: .pair,
                cards: [PokerCard(suit: .hearts, rank: .ace), PokerCard(suit: .diamonds, rank: .ace)],
                description: "Pair: Aces"
            ),
            frameSize: CGSize(width: 393, height: 700)
        )
    }
}
