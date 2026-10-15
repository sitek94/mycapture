import CoreGraphics
import Foundation

/// Draws markups. The editor view and the saved image use the same code, so what you see is what you get.
public enum MarkupRenderer {
    /// Draws into a context whose user space is image pixels with a top-left origin.
    /// `deviceScale` is device pixels per image pixel: shadows are set in device space and must follow the zoom.
    public static func draw(_ markups: [Markup], in context: CGContext, deviceScale: Double) {
        for markup in markups {
            context.saveGState()
            // A soft shadow keeps a markup readable on any background.
            let size = max(markup.width, 4) * deviceScale
            context.setShadow(
                offset: CGSize(width: 0, height: -size * 0.25), blur: size * 0.9, color: CGColor(gray: 0, alpha: 0.35))
            context.setFillColor(markup.color.cgColor)
            switch markup.shape {
            case .arrow(let start, let end):
                context.addPath(ArrowPath.path(from: start, to: end, width: markup.width))
                context.fillPath()
            }
            context.restoreGState()
        }
    }

    /// The image with its markups, at the image's own pixel size and color space.
    public static func render(_ image: CGImage, markups: [Markup]) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let height = Double(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Markups use a top-left origin.
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        draw(markups, in: context, deviceScale: 1)
        return context.makeImage()
    }
}
