import Foundation
import CoreGraphics
import os

private let networkLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.yourapp", category: "Network")

struct FeedbackPayload: Decodable {
    let problem: String
    let analysis: String
    let hints: [String]
    let mistakes: [String]
    let next_step: String
    let encouragement: String
}

struct HighlightAnnotation: Decodable {
    let type: String
    let topLeft: NormalizedPoint
    let width: Float
    let height: Float
    let colorHex: String
    let opacity: Float
    
}


struct NormalizedPoint: Decodable {
    let x: CGFloat
    let y: CGFloat
}




struct AnalyzeResult: Decodable {
    let status: String
    let problem_type: String?
    let context: String?
    let feedback: FeedbackPayload?
    let annotations: [HighlightAnnotation]?
    let annotation_status: String?
    let annotation_error: String?
    let annotation_metadata: [String: String]?
    let error: String?
}

enum NetworkError: Error {
    case invalidURL
    case badStatus(Int)
    case decodingError
}

final class CanvasNetworkManager {

    static let shared = CanvasNetworkManager()
    private init() {}

    // Your ngrok URL or localhost tunnel
    private let baseURL = "https://e5a5b9d00d67.ngrok-free.app"

    func sendCanvasImage(_ pngData: Data) async throws -> AnalyzeResult {

        guard let url = URL(string: "\(baseURL)/analyze-canvas") else {
            throw NetworkError.invalidURL
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // --boundary
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // Content-Disposition
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"canvas.png\"\r\n".data(using: .utf8)!)
        // File type
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        // File data
        body.append(pngData)
        body.append("\r\n".data(using: .utf8)!)

        // --boundary--
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw NetworkError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        
        if let jsonString = String(data: data, encoding: .utf8) {
            networkLogger.debug("[AnalyzeCanvas] Raw response (UTF-8): \(jsonString, privacy: .public)")
        } else {
            networkLogger.info("[AnalyzeCanvas] Received non-UTF8 data with length: \(data.count, privacy: .public)")
        }

        let decoded = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        return decoded
    }
}

