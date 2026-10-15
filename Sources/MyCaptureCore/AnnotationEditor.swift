import CoreGraphics
import Foundation

/// The editor's state and gestures, without any UI: the view converts mouse points to image pixels and calls these.
/// Behavior: a click on a markup selects it in any tool, a click on empty canvas while something
/// is selected only deselects, a drag on empty canvas draws, and a drag shorter than `minimumSize` draws nothing.
public struct AnnotationEditor: Sendable {
    /// In the order of the toolbar. Move only selects and moves; the others also draw.
    public enum Tool: String, CaseIterable, Sendable {
        case move, arrow
    }

    /// Sizes in image pixels for the current zoom, from the view.
    public struct Metrics: Sendable {
        /// Extra distance around a line that still hits it.
        public var tolerance: Double
        /// Distance from a handle's center that grabs it.
        public var handleRadius: Double
        /// A new markup smaller than this on both axes is dropped.
        public var minimumSize: Double

        public init(tolerance: Double, handleRadius: Double, minimumSize: Double) {
            self.tolerance = tolerance
            self.handleRadius = handleRadius
            self.minimumSize = minimumSize
        }
    }

    public var tool: Tool = .arrow
    public var color: MarkupColor
    /// Line width for new markups, in image pixels.
    public var width: Double
    public private(set) var markups: [Markup]
    public private(set) var selection: Markup.ID?
    private var history: History<[Markup]>
    private var drag: Drag?

    private enum Drag: Sendable {
        case creating(Markup.ID)
        case moving(Markup.ID, origin: CGPoint, original: Markup)
        case handle(Markup.ID, Markup.Handle, original: Markup)
    }

    public init(markups: [Markup] = [], color: MarkupColor, width: Double) {
        self.markups = markups
        self.color = color
        self.width = width
        history = History(markups)
    }

    public var isModified: Bool { history.isModified }
    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }
    public var selected: Markup? { markups.first { $0.id == selection } }

    // MARK: Gestures

    /// `duplicate` (⌥ held): a drag on a markup moves a copy of it.
    public mutating func mouseDown(at point: CGPoint, metrics: Metrics, duplicate: Bool = false) {
        if let selected, let handle = selected.handles.first(where: { hypot($0.1.x - point.x, $0.1.y - point.y) <= metrics.handleRadius }) {
            drag = .handle(selected.id, handle.0, original: selected)
            return
        }
        if var hit = markups.last(where: { $0.contains(point, tolerance: metrics.tolerance) }) {
            if duplicate {
                hit.id = UUID()
                markups.append(hit)
            }
            selection = hit.id
            drag = .moving(hit.id, origin: point, original: hit)
            return
        }
        if selection != nil || tool == .move {
            selection = nil
            return
        }
        let markup = Markup(shape: .arrow(start: point, end: point), color: color, width: width)
        markups.append(markup)
        drag = .creating(markup.id)
    }

    /// `constrain` (⇧ held): lines snap to 45°, moves keep to one axis.
    public mutating func mouseDragged(to point: CGPoint, constrain: Bool = false) {
        switch drag {
        case .creating(let id):
            update(id) { markup in
                guard case .arrow(let start, _) = markup.shape else { return markup }
                return markup.moving(.end, to: constrain ? Geometry.snapped45(from: start, to: point) : point)
            }
        case .moving(let id, let origin, let original):
            var delta = CGVector(dx: point.x - origin.x, dy: point.y - origin.y)
            if constrain {
                if abs(delta.dx) > abs(delta.dy) { delta.dy = 0 } else { delta.dx = 0 }
            }
            update(id) { _ in original.moved(by: delta) }
        case .handle(let id, let handle, let original):
            update(id) { _ in
                guard constrain, case .arrow(let start, let end) = original.shape else { return original.moving(handle, to: point) }
                return original.moving(handle, to: Geometry.snapped45(from: handle == .start ? end : start, to: point))
            }
        case nil:
            break
        }
    }

    public mutating func mouseUp(metrics: Metrics) {
        defer { drag = nil }
        if case .creating(let id) = drag, let markup = markups.first(where: { $0.id == id }) {
            guard case .arrow(let start, let end) = markup.shape,
                abs(end.x - start.x) >= metrics.minimumSize || abs(end.y - start.y) >= metrics.minimumSize
            else {
                markups.removeAll { $0.id == id }
                return
            }
            selection = id
        }
        history.record(markups)
    }

    // MARK: Commands

    public mutating func deselect() {
        selection = nil
    }

    public mutating func deleteSelection() {
        guard let selection else { return }
        markups.removeAll { $0.id == selection }
        self.selection = nil
        history.record(markups)
    }

    public mutating func nudgeSelection(by delta: CGVector) {
        guard let selection else { return }
        update(selection) { $0.moved(by: delta) }
        history.record(markups)
    }

    /// Sets the color for new markups and for the selected one.
    public mutating func setColor(_ color: MarkupColor) {
        self.color = color
        guard let selection else { return }
        update(selection) { markup in
            var copy = markup
            copy.color = color
            return copy
        }
        history.record(markups)
    }

    /// Sets the width for new markups and for the selected one.
    public mutating func setWidth(_ width: Double) {
        self.width = width
        guard let selection else { return }
        update(selection) { markup in
            var copy = markup
            copy.width = width
            return copy
        }
        history.record(markups)
    }

    /// The markups are on disk now: closing asks nothing until the next change; undo still works.
    public mutating func markSaved() {
        history.markSaved()
    }

    public mutating func undo() {
        guard let state = history.undo() else { return }
        restore(state)
    }

    public mutating func redo() {
        guard let state = history.redo() else { return }
        restore(state)
    }

    private mutating func restore(_ state: [Markup]) {
        drag = nil
        markups = state
        if let selection, !state.contains(where: { $0.id == selection }) { self.selection = nil }
    }

    private mutating func update(_ id: Markup.ID, _ change: (Markup) -> Markup) {
        guard let index = markups.firstIndex(where: { $0.id == id }) else { return }
        markups[index] = change(markups[index])
    }
}
