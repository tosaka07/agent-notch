enum PermissionDecision: Equatable, Sendable {
    case approve
    case deny
    case terminal
    case dismiss
}

/// Tracks one in-flight decision so clicks and hotkeys cannot submit twice.
///
/// The selected decision remains available to the view while it displays a
/// `ProgressView`; `finish()` returns the banner to its idle state when delivery
/// fails and the expired presentation must remain visible.
struct PermissionSubmissionState: Equatable, Sendable {
    private(set) var decision: PermissionDecision?

    var isSubmitting: Bool { decision != nil }

    mutating func begin(_ decision: PermissionDecision) -> Bool {
        guard self.decision == nil else { return false }
        self.decision = decision
        return true
    }

    mutating func finish() {
        decision = nil
    }
}
