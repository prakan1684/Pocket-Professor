import Foundation
import CoreGraphics

struct FeedbackPayload: Decodable {
    let problem: String
    let analysis: String
    let hints: [String]
    let mistakes: [String]
    let next_step: String
    let encouragement: String
}

enum AnnotationType: String, Decodable {
    case circle
    case rect
    case arrow
    case text
}

struct NormalizedPoint: Decodable {
    let x: CGFloat
    let y: CGFloat
}

struct Annotation: Decodable, Identifiable {
    let id: UUID
    let type: AnnotationType
    let center: NormalizedPoint?
    let radius: CGFloat?
    let origin: NormalizedPoint?
    let size: NormalizedPoint?
    let start: NormalizedPoint?
    let end: NormalizedPoint?
    let colorHex: String?
    let lineWidth: CGFloat?
    // Text-specific
    let text: String?
    let textSize: CGFloat?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Decode straightforward values or collect into locals first
        let decodedId = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let decodedType = try c.decode(AnnotationType.self, forKey: .type)
        let decodedColorHex = try? c.decode(String.self, forKey: .colorHex)
        let decodedLineWidth = try? c.decode(CGFloat.self, forKey: .lineWidth)
        let decodedText = try? c.decode(String.self, forKey: .text)

        // textSize may come from fontSize or textSize
        var textSizeValue: CGFloat?
        if let fs = try? c.decode(CGFloat.self, forKey: .fontSize) {
            textSizeValue = fs
        } else {
            textSizeValue = try? c.decode(CGFloat.self, forKey: .textSize)
        }

        // Center may come from .center or .position (alias for text)
        var centerValue: NormalizedPoint? = try? c.decode(NormalizedPoint.self, forKey: .center)
        if centerValue == nil, let pos = try? c.decode(NormalizedPoint.self, forKey: .position) {
            centerValue = pos
        }

        // Radius
        let radiusValue: CGFloat? = try? c.decode(CGFloat.self, forKey: .radius)

        // Rect origin may be .origin or .topLeft
        var originValue: NormalizedPoint? = try? c.decode(NormalizedPoint.self, forKey: .origin)
        if originValue == nil {
            originValue = try? c.decode(NormalizedPoint.self, forKey: .topLeft)
        }

        // Rect size may be .size or width/height pair
        var sizeValue: NormalizedPoint?
        if let width = try? c.decode(CGFloat.self, forKey: .width),
           let height = try? c.decode(CGFloat.self, forKey: .height) {
            sizeValue = NormalizedPoint(x: width, y: height)
        } else {
            sizeValue = try? c.decode(NormalizedPoint.self, forKey: .size)
        }

        // Arrow start/end may be .start/.end or .from/.to
        var startValue: NormalizedPoint? = try? c.decode(NormalizedPoint.self, forKey: .start)
        if startValue == nil {
            startValue = try? c.decode(NormalizedPoint.self, forKey: .from)
        }
        var endValue: NormalizedPoint? = try? c.decode(NormalizedPoint.self, forKey: .end)
        if endValue == nil {
            endValue = try? c.decode(NormalizedPoint.self, forKey: .to)
        }

        // Finally assign to let properties exactly once
        id = decodedId
        type = decodedType
        colorHex = decodedColorHex
        lineWidth = decodedLineWidth
        text = decodedText
        textSize = textSizeValue
        center = centerValue
        radius = radiusValue
        origin = originValue
        size = sizeValue
        start = startValue
        end = endValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case center
        case radius
        case origin
        case size
        case start
        case end
        case colorHex
        case lineWidth
        case text
        case textSize
        case fontSize // backend alias for textSize
        case topLeft  // backend alias for origin
        case width    // backend width for rect
        case height   // backend height for rect
        case from     // backend alias for start
        case to       // backend alias for end
        case position // backend alias for center (text)
    }
}

struct AnalyzeResult: Decodable {
    let status: String
    let problem_type: String?
    let context: String?
    let feedback: FeedbackPayload?
    let annotations: [Annotation]?
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
        
        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("[AnalyzeCanvas] Raw response:\n\(jsonString)")
        } else {
            print("[AnalyzeCanvas] Received non-UTF8 data with length: \(data.count)")
        }
        #endif

        let decoded = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        return decoded
    }
}

