import Foundation

public final class UsageStateMachine {
    public private(set) var currentState: UsageState

    public init(initialState: UsageState = .noTarget) {
        self.currentState = initialState
    }

    public enum Event {
        case targetEnteredForeground(bundleId: String)
        case targetLeftForeground
        case userBecameIdle
        case userResumedActivity
        case screenLocked
        case screenUnlocked
        case warningThresholdReached
        case limitReached
        case sessionClosed
    }

    @discardableResult
    public func transition(with event: Event) -> UsageState {
        switch (currentState, event) {
        // From NO_TARGET
        case (.noTarget, .targetEnteredForeground):
            currentState = .active

        // From ACTIVE
        case (.active, .targetLeftForeground):
            currentState = .noTarget
        case (.active, .userBecameIdle):
            currentState = .idle
        case (.active, .screenLocked):
            currentState = .paused
        case (.active, .warningThresholdReached):
            currentState = .warning
        case (.active, .limitReached):
            currentState = .limitReached

        // From IDLE
        case (.idle, .userResumedActivity):
            currentState = .active
        case (.idle, .targetLeftForeground):
            currentState = .noTarget
        case (.idle, .screenLocked):
            currentState = .paused

        // From PAUSED
        case (.paused, .screenUnlocked):
            currentState = .active
        case (.paused, .targetLeftForeground):
            currentState = .noTarget

        // From WARNING
        case (.warning, .limitReached):
            currentState = .limitReached
        case (.warning, .targetLeftForeground):
            currentState = .noTarget
        case (.warning, .userBecameIdle):
            currentState = .idle
        case (.warning, .screenLocked):
            currentState = .paused

        // From LIMIT_REACHED
        case (.limitReached, .targetLeftForeground):
            currentState = .noTarget
        case (.limitReached, .screenLocked):
            currentState = .paused

        // Force Session Closed
        case (_, .sessionClosed):
            currentState = .noTarget

        // Ignore invalid transitions
        default:
            break
        }

        return currentState
    }

    public func reset() {
        currentState = .noTarget
    }
}
