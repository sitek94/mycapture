// Renders the app icon's two glyph layers (1024 × 1024 PNGs on a transparent background) from our own drawing in
// Sources/MyCapture/Glyph.swift: camera.png in white (front) and brackets.png in cyan 800 (back).
// usage: scripts/make-icon.sh (renders the layers, then builds the icon)
import AppKit
import SwiftUI

@main
struct MakeGlyph {
    @MainActor static func main() throws {
        let folder = URL(filePath: CommandLine.arguments[1])
        // Cyan 800: the 600 shade almost disappeared into the 400 → 600 gradient under the glass.
        let shade800 = Color(red: 0x15 / 255, green: 0x5E / 255, blue: 0x75 / 255)
        try write(CameraBody().fill(.white, style: FillStyle(eoFill: true)), to: folder.appending(path: "camera.png"))
        try write(ViewfinderBrackets().fill(shade800), to: folder.appending(path: "brackets.png"))
    }

    /// One layer: the glyph at 70% of the 1024 canvas, centered.
    @MainActor static func write(_ layer: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: layer.frame(width: 720, height: 720).frame(width: 1024, height: 1024))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
