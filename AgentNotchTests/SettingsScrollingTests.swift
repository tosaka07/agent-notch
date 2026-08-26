import AppKit
import SwiftUI
import Testing

@testable import AgentNotch
@testable import AgentNotchCore

@Suite("Settings scrolling")
@MainActor
struct SettingsScrollingTests {
    @Test("Native sidebar sections contain every destination")
    func nativeSidebarSectionsContainEveryDestination() {
        let groupedTabs =
            [SettingsTab.general]
            + SettingsSidebarSection.allCases.flatMap(\.tabs)

        #expect(groupedTabs == SettingsTab.allCases)
        #expect(
            SettingsSidebarSection.allCases.allSatisfy {
                !$0.title.isEmpty && !$0.tabs.isEmpty
            }
        )
        #expect(Set(SettingsTab.allCases.map(\.iconColor)).count == 7)
        #expect(
            SettingsTab.allCases.allSatisfy {
                NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: nil)
                    != nil
            }
        )
    }

    /// Hooks is the tallest pane — it is what General used to be before the
    /// sessions and hook sections moved out into tabs of their own.
    @Test("Hook settings remain reachable in a constrained window")
    func hookSettingsRemainReachable() {
        let selection = SettingsSelection()
        selection.tab = .hooks

        let hostingView = NSHostingView(
            rootView: SettingsView(selection: selection, sessionManager: SessionManager())
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.contentWidth,
                // Small enough that even the shortest pane has to scroll — the
                // point is that a pane never gets silently cut off.
                height: 140
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let scrollViews = descendants(of: hostingView).compactMap { $0 as? NSScrollView }
        let scrollableView = scrollViews.first { scrollView in
            guard let documentView = scrollView.documentView else { return false }
            return documentView.frame.height > scrollView.contentSize.height
        }

        #expect(scrollableView != nil)
        #expect(scrollableView?.hasVerticalScroller == true)
        #expect(scrollableView?.verticalScroller?.isEnabled == true)
    }

    @Test("Glyph guide remains reachable in a constrained window")
    func glyphGuideRemainsReachable() {
        let hostedSettings = makeHostingView(tab: .glyphs, viewportHeight: 320)

        let scrollViews = descendants(of: hostedSettings.hostingView)
            .compactMap { $0 as? NSScrollView }
        let scrollableView = scrollViews.first { scrollView in
            guard let documentView = scrollView.documentView else { return false }
            return documentView.frame.height > scrollView.contentSize.height
        }

        #expect(scrollableView != nil)
        #expect(scrollableView?.hasVerticalScroller == true)
        #expect(scrollableView?.verticalScroller?.isEnabled == true)
    }

    @Test("Expanded OSS list scrolls inside the fixed-height viewport")
    func expandedOSSListScrollsInsideFixedHeight() {
        let hostingView = NSHostingView(
            rootView: AboutSettings(isShowingOpenSourceLicenses: true)
                .formStyle(.grouped)
                .frame(width: SettingsView.contentWidth)
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.contentWidth,
                height: SettingsWindowSizing.fixedContentHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        let scrollableView = descendants(of: hostingView)
            .compactMap { $0 as? NSScrollView }
            .first { scrollView in
                guard let documentView = scrollView.documentView else { return false }
                return documentView.frame.height > scrollView.contentSize.height
            }

        #expect(scrollableView != nil)
        #expect(scrollableView?.hasVerticalScroller == true)
        #expect(scrollableView?.verticalScroller?.isEnabled == true)
    }

    @Test("Window keeps a fixed content height")
    func windowKeepsFixedContentHeight() {
        #expect(SettingsWindowSizing.fixedContentHeight == 600)
        #expect(
            SettingsWindowSizing.minimumWindowContentWidth
                < SettingsWindowSizing.preferredWindowContentWidth
        )
        #expect(
            SettingsWindowSizing.preferredWindowContentWidth
                < SettingsWindowSizing.maximumWindowContentWidth
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func makeHostingView(
        tab: SettingsTab,
        viewportHeight: CGFloat
    ) -> (
        selection: SettingsSelection,
        window: NSWindow,
        hostingView: NSHostingView<SettingsView>
    ) {
        let selection = SettingsSelection()
        selection.tab = tab
        let hostingView = NSHostingView(
            rootView: SettingsView(selection: selection, sessionManager: SessionManager())
        )
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SettingsView.contentWidth,
                height: viewportHeight
            ),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        return (selection, window, hostingView)
    }
}
