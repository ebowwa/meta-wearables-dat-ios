//
//  ObjectLibraryView.swift
//  CameraAccess
//
//  Grid of learned objects with management options
//

import SwiftUI

struct ObjectLibraryView: View {
    @ObservedObject var trainingService: TrainingService
    @Environment(\.dismiss) var dismiss
    
    @State private var showingDeleteConfirm: String? = nil
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if trainingService.trainedClasses.isEmpty {
                    emptyState
                } else {
                    objectGrid
                }
            }
            .navigationTitle("My Objects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.box")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Objects Yet")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("Teach me to recognize something!")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var objectGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(trainingService.trainedClasses, id: \.self) { label in
                    ObjectCard(
                        label: label,
                        sampleCount: trainingService.knn.samplesPerClass[label] ?? 0,
                        onDelete: { showingDeleteConfirm = label }
                    )
                }
            }
            .padding()
        }
        .alert("Delete \(showingDeleteConfirm ?? "")?", isPresented: .constant(showingDeleteConfirm != nil)) {
            Button("Delete", role: .destructive) {
                if let label = showingDeleteConfirm {
                    trainingService.removeSamples(for: label)
                }
                showingDeleteConfirm = nil
            }
            Button("Cancel", role: .cancel) {
                showingDeleteConfirm = nil
            }
        } message: {
            Text("This will remove all training data for this object.")
        }
    }
}

struct ObjectCard: View {
    let label: String
    let sampleCount: Int
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon placeholder (could be thumbnail in future)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardColor)
                    .frame(height: 100)
                
                Text(String(label.prefix(2)).uppercased())
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Label
            Text(label)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            // Sample count
            HStack(spacing: 4) {
                Image(systemName: "photo.stack")
                    .font(.caption)
                Text("\(sampleCount) samples")
                    .font(.caption)
            }
            .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var cardColor: Color {
        // Generate consistent color from label
        let hash = abs(label.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.7)
    }
}

// MARK: - Minimized Library Button

struct ObjectLibraryButton: View {
    let objectCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "cube.box.fill")
                Text("\(objectCount)")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}

#Preview {
    ObjectLibraryView(trainingService: TrainingService())
}
