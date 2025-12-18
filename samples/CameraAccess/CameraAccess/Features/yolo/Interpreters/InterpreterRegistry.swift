/*
 * InterpreterRegistry.swift
 * CameraAccess
 *
 * Factory for creating detection interpreters based on model type.
 */

import Foundation

/// Registry for detection interpreters
final class InterpreterRegistry {
    
    // MARK: - Singleton
    
    static let shared = InterpreterRegistry()
    
    // MARK: - Registered Interpreters
    
    private lazy var passthrough = PassthroughInterpreter()
    
    // MARK: - Factory
    
    /// Get the appropriate interpreter for a model type
    func interpreter(for modelType: YOLOModelType) -> any DetectionInterpreter {
        switch modelType {
        case .generic, .faceClassification, .custom:
            return passthrough
        }
    }
    
    /// Get interpreter for a model
    func interpreter(for model: YOLOModelInfo) -> any DetectionInterpreter {
        interpreter(for: model.modelType)
    }
    
    // MARK: - All Interpreters
    
    /// All registered interpreters
    var allInterpreters: [any DetectionInterpreter] {
        [passthrough]
    }
}
