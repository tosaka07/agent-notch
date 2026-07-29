import AgentNotchCore

/// Decides which usage gauges exist and what each one shows.
///
/// # Why this is a type of its own
/// The rule it encodes is a product promise rather than a layout detail: **a gauge's presence
/// depends only on settings, never on whether the fetch succeeded.** A gauge that vanishes when
/// the fetch fails is indistinguishable from a feature that was removed, leaving the user with no
/// surface to read an explanation from — which is exactly how an expired Claude token used to
/// present itself as "usage display is gone".
///
/// Keeping it out of the view body makes that promise directly testable, so a future refactor
/// cannot quietly reintroduce a disappearing gauge.
enum UsageGaugeSurface {
    struct Item: Identifiable, Equatable {
        let agentType: AgentType
        /// nil when there is no value — either still loading, or unavailable.
        let percent: Double?
        /// Why there is no value. nil means the value arrived, or the first poll is still in
        /// flight; `isUnavailable` distinguishes those two.
        let reason: UsageUnavailableReason?

        var isUnavailable: Bool { reason != nil }

        var id: AgentType { agentType }
    }

    /// - Parameters:
    ///   - snapshot: nil before the first poll returns, which shows as loading rather than failure.
    ///   - metric: which window the gauge shows, from settings.
    ///   - codexIntegrationEnabled: the one thing that legitimately removes a gauge — the user
    ///     switched Codex off, so there is nothing to explain.
    static func items(
        snapshot: UsageSnapshot?,
        metric: UsageGaugeMetric,
        codexIntegrationEnabled: Bool
    ) -> [Item] {
        let agentTypes: [AgentType] = codexIntegrationEnabled ? [.claudeCode, .codex] : [.claudeCode]

        guard let snapshot else {
            return agentTypes.map { Item(agentType: $0, percent: nil, reason: nil) }
        }

        return agentTypes.map { agentType in
            let window = snapshot.primaryWindow(for: agentType, metric: metric)
            return Item(
                agentType: agentType,
                percent: window?.usedPercent,
                // A window means there is nothing to explain. Without one, the reason recorded by
                // the fetch is used; an unclassified failure falls back to "no limit to report",
                // the only benign way to reach this point.
                reason: window == nil ? (snapshot.unavailableReason(for: agentType) ?? .noLimits) : nil
            )
        }
    }
}
