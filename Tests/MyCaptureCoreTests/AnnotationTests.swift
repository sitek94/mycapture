import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import MyCaptureCore

struct AnnotationEditorTests {
    let metrics = AnnotationEditor.Metrics(tolerance: 6, handleRadius: 11, minimumSize: 5)
    let red = MarkupColor.palette[0].color

    func editor() -> AnnotationEditor {
        AnnotationEditor(color: red, width: 8)
    }

    func drag(_ editor: inout AnnotationEditor, _ from: CGPoint, _ to: CGPoint, constrain: Bool = false) {
        editor.mouseDown(at: from, metrics: metrics)
        editor.mouseDragged(to: to, constrain: constrain)
        editor.mouseUp(metrics: metrics)
    }

    @Test func aDragDrawsASelectedArrow() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60))
        #expect(editor.markups.count == 1)
        #expect(editor.markups[0].shape == .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 60)))
        #expect(editor.selection == editor.markups[0].id)
        #expect(editor.isModified)
    }

    @Test func aDragShorterThanTheMinimumDrawsNothing() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 13, y: 14))
        #expect(editor.markups.isEmpty)
        #expect(!editor.isModified)
    }

    @Test func shiftSnapsTheArrowTo45Degrees() throws {
        var editor = editor()
        drag(&editor, .zero, CGPoint(x: 100, y: 90), constrain: true)
        guard case .arrow(_, let end) = editor.markups[0].shape else { throw TestFailure() }
        #expect(abs(end.x - end.y) < 0.001)
        #expect(abs(hypot(end.x, end.y) - hypot(100, 90)) < 0.001)
    }

    @Test func theMoveToolDrawsNothingButStillMoves() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.deselect()
        editor.tool = .move
        drag(&editor, CGPoint(x: 10, y: 100), CGPoint(x: 110, y: 100))
        #expect(editor.markups.count == 1)
        drag(&editor, CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 20))
        #expect(editor.markups[0].shape == .arrow(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 110, y: 20)))
    }

    @Test func aClickOnEmptyCanvasOnlyDeselects() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.mouseDown(at: CGPoint(x: 300, y: 300), metrics: metrics)
        editor.mouseUp(metrics: metrics)
        #expect(editor.selection == nil)
        #expect(editor.markups.count == 1)
    }

    @Test func aClickNearTheLineSelectsAndADragMovesIt() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.deselect()
        // 4 px from the line: inside half the width (4) plus the tolerance (6).
        drag(&editor, CGPoint(x: 50, y: 14), CGPoint(x: 60, y: 34))
        #expect(editor.markups[0].shape == .arrow(start: CGPoint(x: 20, y: 30), end: CGPoint(x: 120, y: 30)))
    }

    @Test func aHandleDragMovesOneEnd() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        drag(&editor, CGPoint(x: 112, y: 12), CGPoint(x: 150, y: 80))
        #expect(editor.markups[0].shape == .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 150, y: 80)))
    }

    @Test func optionDragMovesACopy() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.deselect()
        editor.mouseDown(at: CGPoint(x: 50, y: 10), metrics: metrics, duplicate: true)
        editor.mouseDragged(to: CGPoint(x: 50, y: 50))
        editor.mouseUp(metrics: metrics)
        #expect(editor.markups.count == 2)
        #expect(editor.markups[0].shape == .arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 10)))
        #expect(editor.selection == editor.markups[1].id)
    }

    @Test func undoAndRedoStepThroughGestures() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.deleteSelection()
        #expect(editor.markups.isEmpty)
        editor.undo()
        #expect(editor.markups.count == 1)
        editor.undo()
        #expect(editor.markups.isEmpty)
        #expect(!editor.isModified)
        editor.redo()
        #expect(editor.markups.count == 1)
    }

    @Test func undoGoesBackPastASave() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        editor.markSaved()
        #expect(!editor.isModified)
        editor.undo()
        #expect(editor.markups.isEmpty)
        #expect(editor.isModified)
    }

    @Test func aStyleChangeAppliesToTheSelectionAndToNewMarkups() {
        var editor = editor()
        drag(&editor, CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10))
        let blue = MarkupColor.palette[4].color
        editor.setColor(blue)
        editor.setWidth(12)
        #expect(editor.markups[0].color == blue)
        #expect(editor.markups[0].width == 12)
        editor.deselect()
        drag(&editor, CGPoint(x: 10, y: 100), CGPoint(x: 110, y: 100))
        #expect(editor.markups[1].color == blue)
        #expect(editor.markups[1].width == 12)
    }
}

struct HistoryTests {
    @Test func anEqualStateAddsNothing() {
        var history = History(1)
        history.record(1)
        #expect(!history.canUndo)
        history.record(2)
        history.record(2)
        #expect(history.undo() == 1)
        #expect(!history.canUndo)
    }

    @Test func aNewStateDropsTheRedoStates() {
        var history = History(1)
        history.record(2)
        history.undo()
        history.record(3)
        #expect(!history.canRedo)
        #expect(history.undo() == 1)
    }

    @Test func aChangeAfterUndoingPastTheSaveStaysModified() {
        var history = History(1)
        history.record(2)
        history.record(3)
        history.markSaved()
        history.undo()
        history.undo()
        history.record(4)
        #expect(history.isModified)
        history.undo()
        #expect(history.isModified)
    }

    @Test func backAtTheFirstStateIsNotModified() {
        var history = History(1)
        history.record(2)
        #expect(history.isModified)
        history.record(1)
        #expect(!history.isModified)
    }
}

struct AnnotationStoreTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "mycapture-tests-\(UUID().uuidString)")

    /// A 40 × 30 px white PNG at 144 dpi, like a Retina capture.
    func makeCapture() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = try #require(
            CGContext(
                data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = try #require(context.makeImage())
        let file = folder.appending(path: "capture.png")
        try AnnotationStore.png(image, properties: [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144]).write(to: file)
        try ScreenCaptureAttributes.write("selection", ScreenCaptureAttributes.typeKey, to: file)
        return file
    }

    @Test func savingKeepsSizeResolutionAttributesAndTheMarkups() throws {
        let file = try makeCapture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationStore(file: file)
        let loaded = try #require(store.loadImage())
        let arrow = Markup(shape: .arrow(start: CGPoint(x: 2, y: 15), end: CGPoint(x: 38, y: 15)), color: .palette[0].color, width: 4)
        try store.save([arrow], image: loaded.image, properties: loaded.properties)

        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 40)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 30)
        #expect(properties[kCGImagePropertyDPIWidth] as? Double == 144)
        #expect(ScreenCaptureAttributes.read(file)?.kind == .selection)
        #expect(store.loadMarkups() == [arrow])
    }

    @Test func editingAgainStartsFromTheOriginalPixels() throws {
        let file = try makeCapture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationStore(file: file)
        let first = try #require(store.loadImage())
        let arrow = Markup(shape: .arrow(start: CGPoint(x: 2, y: 15), end: CGPoint(x: 38, y: 15)), color: .palette[0].color, width: 4)
        try store.save([arrow], image: first.image, properties: first.properties)
        // The arrow is gone again: the file must be white again, not keep the first arrow.
        let second = try #require(store.loadImage())
        try store.save([], image: second.image, properties: second.properties)
        #expect(pixel(of: try savedImage(file), x: 20, y: 15) == [255, 255, 255, 255])
    }

    @Test func theArrowIsDrawnIntoTheSavedImage() throws {
        let file = try makeCapture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AnnotationStore(file: file)
        let loaded = try #require(store.loadImage())
        let arrow = Markup(shape: .arrow(start: CGPoint(x: 2, y: 15), end: CGPoint(x: 38, y: 15)), color: .palette[0].color, width: 6)
        try store.save([arrow], image: loaded.image, properties: loaded.properties)
        let center = pixel(of: try savedImage(file), x: 20, y: 15)
        #expect(center[0] > 200 && center[1] < 100 && center[2] < 100)
    }

    func savedImage(_ file: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// RGBA of one pixel, top-left origin.
    func pixel(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        }
        return bytes
    }
}

struct TestFailure: Error {}
