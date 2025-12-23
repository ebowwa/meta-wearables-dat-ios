import Foundation
import AppKit

// MARK: - YOLO API Client

class YOLOClient {
    static let shared = YOLOClient()
    
    // Default to localhost, can be configured
    var baseURL = "http://localhost:8000"
    
    struct Detection: Codable, Identifiable {
        let id = UUID()
        let class_id: Int
        let class_name: String
        let confidence: Float
        let bbox: [Float] // [x1, y1, x2, y2]
        let bbox_normalized: [Float] // [cx, cy, w, h]
        
        enum CodingKeys: String, CodingKey {
            case class_id, class_name, confidence, bbox, bbox_normalized
        }
    }
    
    struct InferenceResult: Codable {
        let detections: [Detection]
        let inference_time_ms: Float
    }
    
    func infer(image: NSImage, modelPath: String = "resources/yolov8m.pt") async throws -> InferenceResult {
        guard let url = URL(string: "\(baseURL)/api/v1/infer?model_path=\(modelPath)") else {
            throw URLError(.badURL)
        }
        
        // Convert NSImage to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw NSError(domain: "YOLOClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }
        
        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add image file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let (data, _) = try await URLSession.shared.upload(for: request, from: body)
        
        // Parse response
        let result = try JSONDecoder().decode(InferenceResult.self, from: data)
        return result
    }
}
