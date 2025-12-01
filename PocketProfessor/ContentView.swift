import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

struct ContentView: View {
    @State private var canvasView = PKCanvasView()
    @State private var feedback = ""
    @State private var isLoading = false

    @State private var resultStatus: String?
    @State private var resultProblemType: String?
    @State private var resultContext: String?
    @State private var resultFeedbackPayload: FeedbackPayload?
    @State private var errorMessage: String?
    @State private var resultAnnotations: [Annotation] = []
    @State private var annotationError: String?

    var body: some View {
        VStack(spacing: 12) {
            CanvasView(canvasView: $canvasView)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    AnnotationOverlay(annotations: resultAnnotations)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button("Ask Pocket Professor") {
                    Task {
                        await analyzeCanvas()
                    }
                }
                .disabled(isLoading)

                Button("Clear") {
                    canvasView.drawing = PKDrawing()
                    feedback = ""
                }
                .disabled(isLoading)
            }
            .font(.headline)

            if let errorMessage, !errorMessage.isEmpty {
                Text("Error: \(errorMessage)")
                    .padding(.horizontal)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.red)
            } else if resultStatus != nil {
                FeedbackView(
                    problemType: resultProblemType,
                    context: resultContext,
                    feedback: resultFeedbackPayload
                )
                .padding(.horizontal)
                if let annotationError, !annotationError.isEmpty {
                    Text("Annotation error: \(annotationError)")
                        .font(.footnote)
                        .foregroundColor(.orange)
                        .padding(.horizontal)
                }
            } else if !feedback.isEmpty {
                // Fallback to legacy string feedback if present
                Text(feedback)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
        }
        .padding()
    }

    private func analyzeCanvas() async {
        isLoading = true
        feedback = ""
        defer { isLoading = false }

        // Render the drawing over a white background to avoid transparency
        let bounds = canvasView.bounds
        let scale: CGFloat = UIScreen.main.scale
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        UIGraphicsBeginImageContextWithOptions(bounds.size, true, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            feedback = "Failed to create graphics context."
            UIGraphicsEndImageContext()
            return
        }

        // Fill background white
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounds.size))

        // Draw the PencilKit rendered image on top
        let rendered = canvasView.drawing.image(from: bounds, scale: scale)
        rendered.draw(in: CGRect(origin: .zero, size: bounds.size))

        guard let composed = UIGraphicsGetImageFromCurrentImageContext(),
              let image = composed.pngData() else {
            feedback = "Failed to compose image."
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()

        do {
            let result = try await CanvasNetworkManager.shared.sendCanvasImage(image)
            if result.status.lowercased() == "ok" || result.status.lowercased() == "success" {
                resultStatus = result.status
                resultProblemType = result.problem_type
                resultContext = result.context
                resultFeedbackPayload = result.feedback
                resultAnnotations = result.annotations ?? []
                annotationError = result.annotation_error
                errorMessage = nil
                feedback = "" // clear legacy string
            } else {
                errorMessage = result.error ?? "Request failed with status: \(result.status)"
                resultStatus = nil
                resultProblemType = nil
                resultContext = nil
                resultFeedbackPayload = nil
                resultAnnotations = []
                annotationError = nil
                feedback = ""
            }
        } catch {
            errorMessage = error.localizedDescription
            resultStatus = nil
            resultProblemType = nil
            resultContext = nil
            resultFeedbackPayload = nil
            resultAnnotations = []
            annotationError = nil
            feedback = ""
        }
    }
}

struct FeedbackView: View {
    let problemType: String?
    let context: String?
    let feedback: FeedbackPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problemType, !problemType.isEmpty {
                Text("Problem Type")
                    .font(.headline)
                Text(problemType)
                    .foregroundStyle(.secondary)
            }

            if let context, !context.isEmpty {
                Text("Context")
                    .font(.headline)
                    .padding(.top, 6)
                Text(context)
                    .foregroundStyle(.secondary)
            }

            if let fb = feedback {
                if !fb.problem.isEmpty {
                    Text("Problem")
                        .font(.headline)
                        .padding(.top, 6)
                    Text(fb.problem)
                        .foregroundStyle(.secondary)
                }
                if !fb.analysis.isEmpty {
                    Text("Analysis")
                        .font(.headline)
                        .padding(.top, 6)
                    Text(fb.analysis)
                        .foregroundStyle(.secondary)
                }
                if !fb.hints.isEmpty {
                    Text("Hints")
                        .font(.headline)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fb.hints, id: \.self) { hint in
                            Text("• \(hint)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !fb.mistakes.isEmpty {
                    Text("Mistakes")
                        .font(.headline)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(fb.mistakes, id: \.self) { item in
                            Text("• \(item)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !fb.next_step.isEmpty {
                    Text("Next Step")
                        .font(.headline)
                        .padding(.top, 6)
                    Text(fb.next_step)
                        .foregroundStyle(.secondary)
                }
                if !fb.encouragement.isEmpty {
                    Text("Encouragement")
                        .font(.headline)
                        .padding(.top, 6)
                    Text(fb.encouragement)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnnotationOverlay: View {
    let annotations: [Annotation]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(annotations) { ann in
                    switch ann.type {
                    case .circle:
                        if let c = ann.center, let r = ann.radius {
                            Circle()
                                .stroke(color(from: ann.colorHex) ?? .red, lineWidth: ann.lineWidth ?? 3)
                                .frame(width: 2 * r * size.width, height: 2 * r * size.height)
                                .position(x: c.x * size.width, y: c.y * size.height)
                        }
                    case .rect:
                        if let o = ann.origin, let s = ann.size {
                            let rect = CGRect(
                                x: o.x * size.width,
                                y: o.y * size.height,
                                width: s.x * size.width,
                                height: s.y * size.height
                            )
                            Path { path in
                                path.addRect(rect)
                            }
                            .stroke(color(from: ann.colorHex) ?? .red, lineWidth: ann.lineWidth ?? 3)
                        }
                    case .arrow:
                        if let start = ann.start, let end = ann.end {
                            ArrowShape(
                                start: CGPoint(x: start.x * size.width, y: start.y * size.height),
                                end: CGPoint(x: end.x * size.width, y: end.y * size.height)
                            )
                            .stroke(color(from: ann.colorHex) ?? .red, lineWidth: ann.lineWidth ?? 3)
                        }
                    case .text:
                        if let c = ann.center, let text = ann.text {
                            let fontSize = ann.textSize ?? 14
                            Text(text)
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundColor(color(from: ann.colorHex) ?? .blue)
                                .padding(4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .position(x: c.x * size.width, y: c.y * size.height)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func color(from hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        return Color(hex: hex)
    }
}

struct ArrowShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 12
        let arrowAngle: CGFloat = .pi / 7
        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
        return path
    }
}

extension Color {
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if hex.count == 6 { hex = "FF" + hex }
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let a = Double((int >> 24) & 0xFF) / 255.0
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b, opacity: a)
    }
}
