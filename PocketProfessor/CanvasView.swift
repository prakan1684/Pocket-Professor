//
//  CanvasView.swift
//  PocketProfessor
//
//  Created by Pranav Kandikonda on 11/7/25.
//

import SwiftUI
import PencilKit

struct PKCanvasRepresentable: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        // Configure the provided PKCanvasView instance
        canvasView.backgroundColor = .systemBackground
        canvasView.isOpaque = true
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.tool = PKInkingTool(.pen, color: .label, width: 4)
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No-op for now; the binding provides the same instance
    }
}
