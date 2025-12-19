//
//  ObjectLibraryView.swift
//  CameraAccess
//
//  Game-style inventory grid of learned objects (GTA/Minecraft chest style)
//

import SwiftUI

struct ObjectLibraryView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedObject: String? = nil
    @State private var showingDeleteConfirm = false
    
    // Inventory grid: 4 columns x 6 rows = 24 slots
    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
    let totalSlots = 24
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                // Inventory chest
                inventoryGrid
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(white: 0.3), lineWidth: 2)
                            )
                    )
                    .padding()
                
                // Selected object info
                if let selected = selectedObject {
                    objectInfo(for: selected)
                }
                
                Spacer()
            }
        }
        .alert("Delete \(selectedObject ?? "")?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let obj = selectedObject {
                    trainingService.removeSamples(for: obj)
                    selectedObject = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var header: some View {
        HStack {
            Text("📦 Inventory")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
    
    private var inventoryGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // Filled slots
            ForEach(trainingService.trainedClasses, id: \.self) { label in
                InventorySlot(
                    label: label,
                    sampleCount: trainingService.knn.samplesPerClass[label] ?? 0,
                    isSelected: selectedObject == label
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selectedObject = selectedObject == label ? nil : label
                    }
                }
            }
            
            // Empty slots
            ForEach(0..<emptySlotCount, id: \.self) { _ in
                EmptySlot()
            }
        }
    }
    
    private var emptySlotCount: Int {
        max(0, totalSlots - trainingService.trainedClasses.count)
    }
    
    private func objectInfo(for label: String) -> some View {
        VStack(spacing: 12) {
            // Name
            Text(label)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            // Stats
            HStack(spacing: 20) {
                StatBadge(icon: "photo.stack", value: "\(trainingService.knn.samplesPerClass[label] ?? 0)", label: "samples")
            }
            
            // Actions
            HStack(spacing: 16) {
                Button(action: { showingDeleteConfirm = true }) {
                    Label("Delete", systemImage: "trash")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

// MARK: - Inventory Slot (Filled)

struct InventorySlot: View {
    let label: String
    let sampleCount: Int
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Slot background
            RoundedRectangle(cornerRadius: 4)
                .fill(slotColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.yellow : Color(white: 0.4), lineWidth: isSelected ? 2 : 1)
                )
            
            // Item icon
            VStack(spacing: 2) {
                Text(String(label.prefix(2)).uppercased())
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                // Sample count badge
                Text("\(sampleCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(3)
            }
        }
        .frame(height: 60)
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
    
    private var slotColor: Color {
        // Generate color from label hash
        let hash = abs(label.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.5, brightness: 0.35)
    }
}

// MARK: - Empty Slot

struct EmptySlot: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(white: 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(white: 0.2), lineWidth: 1)
            )
            .frame(height: 60)
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.system(.caption, design: .monospaced))
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
        }
        .foregroundColor(.white)
    }
}

// MARK: - Library Button (Compact)

struct ObjectLibraryButton: View {
    let objectCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("📦")
                Text("\(objectCount)/24")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.2))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(white: 0.4), lineWidth: 1)
            )
        }
    }
}

#Preview {
    ObjectLibraryView(trainingService: TrainingService())
}
