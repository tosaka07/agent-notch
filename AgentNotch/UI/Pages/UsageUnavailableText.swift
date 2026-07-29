import AgentNotchCore

/// User-facing wording for "there is no usage to show, and here is why".
///
/// # Why every reason gets its own sentence
/// The gauge never disappears on failure, so the empty state has to carry the explanation
/// instead. A single "Couldn't fetch usage" would leave the user with no idea what to do,
/// while these differ in exactly that: `tokenExpired` names the one action that fixes it
/// (run Claude Code), `noLimits` says nothing is wrong at all, and `rateLimited` says to
/// simply wait.
extension UsageUnavailableReason {
    /// One short sentence for the usage page's section note.
    var explanation: String {
        switch self {
        case .notSignedIn:
            L("Not signed in on this Mac")
        case .tokenExpired:
            // Agent Notch only reads credentials and cannot refresh them, so the fix is to let
            // the agent itself do it. Naming the action beats naming the fault.
            L("The access token expired. Launching Claude Code refreshes it.")
        case .unauthorized:
            L("Authorization was rejected")
        case .rateLimited:
            L("Rate limited. Retrying automatically.")
        case .networkError:
            L("Couldn't reach the server")
        case .noLimits:
            L("No usage limit on this plan")
        case .integrationDisabled:
            L("Turned off in settings")
        case .agentUnreachable:
            L("Couldn't reach the agent on this Mac")
        }
    }

    /// A compact form for the gauge tooltip, where the agent name already precedes it.
    var shortLabel: String {
        switch self {
        case .notSignedIn: L("Not signed in")
        case .tokenExpired: L("Token expired")
        case .unauthorized: L("Unauthorized")
        case .rateLimited: L("Rate limited")
        case .networkError: L("Offline")
        case .noLimits: L("No limit")
        case .integrationDisabled: L("Off")
        case .agentUnreachable: L("Unreachable")
        }
    }
}
