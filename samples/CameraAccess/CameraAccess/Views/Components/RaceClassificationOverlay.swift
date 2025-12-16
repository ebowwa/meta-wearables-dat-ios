/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI

/// Overlay view that displays race classification results
struct RaceClassificationOverlay: View {
    let classification: ClassifiedFace?
    let isEnabled: Bool
    
    var body: some View {
        VStack {
            if isEnabled {
                if let result = classification {
                    ClassificationBadge(result: result)
                } else {
                    LoadingBadge()
                }
            }
            Spacer()
        }
        .padding(.top, 60)
    }
}

/// Badge showing classification result with confidence
struct ClassificationBadge: View {
    let result: ClassifiedFace
    
    private var backgroundColor: Color {
        // Color based on confidence level
        if result.confidence >= 0.8 {
            return .green.opacity(0.9)
        } else if result.confidence >= 0.5 {
            return .blue.opacity(0.9)
        } else {
            return .orange.opacity(0.9)
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Main classification
            HStack(spacing: 8) {
                Text(result.category.emoji)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.category.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("\(Int(result.confidence * 100))% confidence")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Top 3 alternatives
            if result.topCategories.count > 1 {
                Divider()
                    .background(Color.white.opacity(0.3))
                
                HStack(spacing: 12) {
                    ForEach(result.topCategories.dropFirst().prefix(2), id: \.0) { category, confidence in
                        VStack(spacing: 2) {
                            Text(category.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            Text("\(Int(confidence * 100))%")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        )
    }
}

/// Loading indicator when classification is in progress
struct LoadingBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text("Analyzing...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.8))
        )
    }
}

/// Toggle button for race classification mode
struct RaceClassificationToggle: View {
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: { isEnabled.toggle() }) {
            ZStack {
                Circle()
                    .fill(isEnabled ? Color.purple : Color.gray.opacity(0.6))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
        }
        .accessibilityLabel(isEnabled ? "Disable race classification" : "Enable race classification")
    }
}

#Preview {
    ZStack {
        Color.black
        
        RaceClassificationOverlay(
            classification: ClassifiedFace(
                category: .eastAsian,
                confidence: 0.78,
                allConfidences: [
                    .eastAsian: 0.78,
                    .southeastAsian: 0.12,
                    .white: 0.05,
                    .latinoHispanic: 0.03,
                    .indian: 0.01,
                    .black: 0.005,
                    .middleEastern: 0.005
                ]
            ),
            isEnabled: true
        )
    }
}
