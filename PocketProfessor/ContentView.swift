import SwiftUI
import PencilKit
import os

private let uiLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.yourapp", category: "UI")
private let networkLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.yourapp", category: "Network")

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
    @State private var highlights: [HighlightAnnotation] = []

    @State private var resultStatus: String?
    @State private var resultProblemType: String?
    @State private var resultContext: String?
    @State private var resultFeedbackPayload: FeedbackPayload?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            CanvasView(canvasView: $canvasView)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 20) {
                Button("Ask Pocket Professor") {
                    print("Button pressed")
                    uiLogger.info("Ask Pocket Professor button tapped")
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
            } else if !feedback.isEmpty {
                // Fallback to legacy string feedback if present
                Text(feedback)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            uiLogger.info("ContentView appeared")
        }
        .padding()
        .overlay{
            GeometryReader { geo in
                ForEach(highlights.indices, id: \.self) { idx in
                    let h = highlights[idx]
                    let x = h.topLeft.x * geo.size.width
                    let y = h.topLeft.y * geo.size.height
                    let w = CGFloat(h.width) * geo.size.width
                    let hgt = CGFloat(h.height) * geo.size.height
                    Rectangle()
                        .fill(Color.yellow.opacity(Double(h.opacity)))
                        .frame(width: w, height: hgt)
                        .position(x: x + w/2, y: y + hgt/2)
                }
            }
            .allowsHitTesting(false)
        }
        
    }

    private func analyzeCanvas() async {
        uiLogger.info("analyzeCanvas started")
        isLoading = true
        defer {
            isLoading = false
            uiLogger.info("analyzeCanvas finished")
        }
        feedback = ""

        // Render the drawing over a white background to avoid transparency
        let bounds = canvasView.bounds
        let scale: CGFloat = UIScreen.main.scale
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        uiLogger.debug("Preparing graphics context with size: \(String(describing: bounds.size)) scale: \(scale, privacy: .public)")

        UIGraphicsBeginImageContextWithOptions(bounds.size, true, scale)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            uiLogger.error("Failed to create graphics context")
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
        
        uiLogger.debug("Rendered drawing into context")

        guard let composed = UIGraphicsGetImageFromCurrentImageContext(),
              let image = composed.pngData() else {
            uiLogger.error("Failed to compose PNG image from drawing")
            feedback = "Failed to compose image."
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()

        do {
            networkLogger.info("Sending canvas image to server (bytes: \(image.count, privacy: .public))")
            let result = try await CanvasNetworkManager.shared.sendCanvasImage(image)
            networkLogger.info("Received response status: \(result.status, privacy: .public)")
            if result.status.lowercased() == "ok" || result.status.lowercased() == "success" {
                networkLogger.debug("Assigning result payload; annotations: \(result.annotations?.count ?? 0, privacy: .public)")
                resultStatus = result.status
                resultProblemType = result.problem_type
                resultContext = result.context
                resultFeedbackPayload = result.feedback
                highlights = result.annotations ?? []
                networkLogger.debug("Highlights assigned: \(highlights.count, privacy: .public)")
                errorMessage = nil
                feedback = "" // clear legacy string
            } else {
                networkLogger.error("Server returned failure status: \(result.status, privacy: .public) error: \(result.error ?? "<none>", privacy: .public)")
                errorMessage = result.error ?? "Request failed with status: \(result.status)"
                resultStatus = nil
                resultProblemType = nil
                resultContext = nil
                resultFeedbackPayload = nil
                feedback = ""
            }
        } catch {
            networkLogger.error("Network/processing error: \(String(describing: error), privacy: .public)")
            errorMessage = error.localizedDescription
            resultStatus = nil
            resultProblemType = nil
            resultContext = nil
            resultFeedbackPayload = nil
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

