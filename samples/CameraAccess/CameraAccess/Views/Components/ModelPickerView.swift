/*
 * ModelPickerView.swift
 * CameraAccess
 *
 * UI for selecting, downloading, and managing YOLO models.
 */

import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: YOLOModelManager
    @State private var showAddRemoteModel = false
    @State private var remoteModelName = ""
    @State private var remoteModelURL = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(modelManager.availableModels) { model in
                        let state = modelManager.downloadStates[model.id] ?? .notDownloaded
                        let isActive = modelManager.activeModel?.id == model.id
                        
                        ModelRowView(
                            model: model,
                            downloadState: state,
                            isActive: isActive,
                            onSelect: {
                                Task {
                                    try? await modelManager.loadModel(model)
                                }
                            },
                            onDownload: {
                                Task {
                                    await modelManager.downloadModel(model)
                                }
                            },
                            onDelete: {
                                modelManager.deleteModel(model)
                            }
                        )
                    }
                } header: {
                    Text("Models")
                } footer: {
                    if modelManager.availableModels.isEmpty {
                        Text("No models available. Add one from the cloud.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("YOLO Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showAddRemoteModel = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddRemoteModel) {
                AddRemoteModelSheet(
                    name: $remoteModelName,
                    url: $remoteModelURL,
                    onAdd: {
                        if let url = URL(string: remoteModelURL), !remoteModelName.isEmpty {
                            modelManager.addRemoteModel(name: remoteModelName, url: url)
                            remoteModelName = ""
                            remoteModelURL = ""
                        }
                        showAddRemoteModel = false
                    }
                )
            }
            .overlay {
                if modelManager.isLoading {
                    LoadingOverlay()
                }
            }
        }
    }
}

// MARK: - Model Row

struct ModelRowView: View {
    let model: YOLOModelInfo
    let downloadState: YOLOModelDownloadState
    let isActive: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(model.source.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor.opacity(0.2))
                        .foregroundColor(sourceColor)
                        .cornerRadius(4)
                    
                    Text("v\(model.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action button based on state
            actionButton
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if case .local = model.source {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        switch downloadState {
        case .notDownloaded:
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 40)
            
        case .downloaded:
            if !isActive {
                Button(action: onSelect) {
                    Text("Use")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
        case .failed(let error):
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
    
    private var sourceColor: Color {
        switch model.source {
        case .bundled: return .green
        case .local: return .blue
        case .remote: return .purple
        }
    }
}

// MARK: - Add Remote Model Sheet

struct AddRemoteModelSheet: View {
    @Binding var name: String
    @Binding var url: String
    let onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Model Info") {
                    TextField("Model Name", text: $name)
                    TextField("Model URL (.mlpackage)", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section {
                    Text("Enter the URL of a .mlpackage or .mlmodelc file hosted on the web.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Cloud Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add", action: onAdd)
                        .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading Model...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

#Preview {
    ModelPickerView(modelManager: YOLOModelManager())
}
