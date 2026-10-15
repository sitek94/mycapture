/// Undo and redo as whole snapshots: each finished gesture or style change adds one.
public struct History<State: Equatable & Sendable>: Sendable {
    private var states: [State]
    private var index = 0
    /// The state last written to disk; nil when a new change replaced it (after an undo past the save).
    private var saved: Int? = 0

    public init(_ initial: State) {
        states = [initial]
    }

    public var current: State { states[index] }
    public var canUndo: Bool { index > 0 }
    public var canRedo: Bool { index < states.count - 1 }
    /// True when the current state differs from the one last saved (or opened).
    public var isModified: Bool { saved.map { states[index] != states[$0] } ?? true }

    /// The current state is on disk now. Undo still goes back past it.
    public mutating func markSaved() {
        saved = index
    }

    /// Adds a state after the current one and drops the redo states. A state equal to the current one adds nothing.
    public mutating func record(_ state: State) {
        guard state != states[index] else { return }
        states.removeSubrange((index + 1)...)
        if let saved, saved > index { self.saved = nil }
        states.append(state)
        index += 1
    }

    @discardableResult
    public mutating func undo() -> State? {
        guard canUndo else { return nil }
        index -= 1
        return states[index]
    }

    @discardableResult
    public mutating func redo() -> State? {
        guard canRedo else { return nil }
        index += 1
        return states[index]
    }
}
