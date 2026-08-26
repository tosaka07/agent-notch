import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Localization")
struct LocalizationTests {
    @Test("Explicit Japanese localizes GUI strings")
    func explicitJapaneseLocalizesGUIStrings() {
        #expect(L("Appearance", language: .japanese) == "表示")
    }

    @Test("Japanese localization preserves interpolated argument order")
    func japaneseLocalizationPreservesInterpolatedArgumentOrder() {
        let agent = "Codex"
        let days = 7
        #expect(
            L("\(agent) over the last \(days) days", language: .japanese)
                == "直近 7 日で Codex"
        )
    }

    @Test("Explicit Japanese localizes Core strings")
    func explicitJapaneseLocalizesCoreStrings() {
        #expect(
            AppLocalization.localized("By urgency", language: .japanese)
                == "要介入順"
        )
    }

    @Test("Japanese explains native permission pass-through")
    func japaneseLocalizesPermissionPassThrough() {
        #expect(
            L("Let the agent handle permissions", language: .japanese)
                == "権限リクエストをエージェント側で処理"
        )
        #expect(
            L(
                "Permission requests bypass Agent Notch and follow the agent’s own approval flow. Questions still appear here.",
                language: .japanese
            )
                == "権限リクエストは Agent Notch を経由せず、エージェント側の承認フローに従います。質問は引き続きここに表示されます。"
        )
    }

    @Test("Japanese localizes formerly hard-coded UI labels and compact durations")
    func japaneseLocalizesRuntimeUILabels() {
        #expect(L("Permission required", language: .japanese) == "権限が必要です")
        #expect(L("Daily cost", language: .japanese) == "日別コスト")
        #expect(L("\(12)s", language: .japanese) == "12秒")
        #expect(L("+\(3) more", language: .japanese) == "ほか3件")
        #expect(L("Usage allowance", language: .japanese) == "使用枠")
        #expect(
            L("Used \("21,987.78") / \("60,000")", language: .japanese)
                == "使用済み 21,987.78 / 60,000"
        )
        #expect(L("\(63) percent remaining", language: .japanese) == "残り 63 パーセント")
    }

    /// The gauge stays visible when usage cannot be fetched, so its explanation is a first-class
    /// string rather than a debug aside — an untranslated one would be the most prominent text on
    /// the page for a Japanese user. Every `UsageUnavailableReason` sentence is pinned here so
    /// adding a reason without translating it fails.
    @Test("Japanese localizes every usage-unavailable reason")
    func japaneseLocalizesUsageUnavailableReasons() {
        #expect(
            L("The access token expired. Launching Claude Code refreshes it.", language: .japanese)
                == "アクセストークンが失効しました。Claude Code を起動すると更新されます。"
        )
        #expect(L("Not signed in on this Mac", language: .japanese) == "この Mac でサインインしていません")
        #expect(L("Authorization was rejected", language: .japanese) == "認証が拒否されました")
        #expect(
            L("Rate limited. Retrying automatically.", language: .japanese)
                == "レート制限中です。自動的に再試行します。"
        )
        #expect(L("Couldn't reach the server", language: .japanese) == "サーバーに接続できませんでした")
        #expect(L("No usage limit on this plan", language: .japanese) == "このプランには使用量の上限がありません")
        #expect(L("Turned off in settings", language: .japanese) == "設定で無効になっています")
        #expect(
            L("Couldn't reach the agent on this Mac", language: .japanese)
                == "この Mac でエージェントに接続できませんでした"
        )

        // The compact forms used in the gauge tooltip.
        #expect(L("Token expired", language: .japanese) == "トークン失効")
        #expect(L("Not signed in", language: .japanese) == "未サインイン")
        #expect(L("Unauthorized", language: .japanese) == "認証エラー")
        #expect(L("Rate limited", language: .japanese) == "レート制限中")
        #expect(L("Offline", language: .japanese) == "オフライン")
        #expect(L("No limit", language: .japanese) == "上限なし")
        #expect(L("Off", language: .japanese) == "オフ")
        #expect(L("Unreachable", language: .japanese) == "接続不可")
    }

    @Test("Explicit English uses source strings")
    func explicitEnglishUsesSourceStrings() {
        #expect(L("Appearance", language: .english) == "Appearance")
        #expect(
            AppLocalization.localized("By urgency", language: .english)
                == "By urgency"
        )
    }

    @Test("Japanese localizes the language restart confirmation")
    func japaneseLocalizesLanguageRestartConfirmation() {
        #expect(
            L("Restart Agent Notch?", language: .japanese)
                == "Agent Notch を再起動しますか？"
        )
        #expect(L("Restart Now", language: .japanese) == "今すぐ再起動")
        #expect(L("Later", language: .japanese) == "後で")
    }

    @Test("Japanese localizes About and license labels")
    func japaneseLocalizesAboutLabels() {
        #expect(L("About", language: .japanese) == "情報")
        #expect(
            L("Open Source Licenses", language: .japanese)
                == "オープンソースライセンス"
        )
        #expect(L("Version \("1.2.3")", language: .japanese) == "バージョン 1.2.3")
    }
}
