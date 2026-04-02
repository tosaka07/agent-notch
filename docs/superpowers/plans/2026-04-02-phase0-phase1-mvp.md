# Phase 0 + Phase 1: Agent Notch MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS notch overlay app that monitors Claude Code sessions in real-time — showing status, current tool, token usage, and cost — with GUI-based permission approval.

**Architecture:** Native Swift macOS app using NSPanel (AppKit) for the notch overlay window, SwiftUI for all UI content, Network.framework for Unix socket IPC with Claude Code hooks, and a unified event model for future multi-agent support.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit (NSPanel), Network.framework (NWListener/NWConnection), Defaults, LaunchAtLogin-Modern, Sparkle 2

---

## File Structure

```
AgentNotch/
├── AgentNotch.xcodeproj
├── AgentNotch/
│   ├── App/
│   │   ├── AgentNotchApp.swift          # @main, AppDelegate setup
│   │   ├── AppDelegate.swift            # NSPanel lifecycle, status item
│   │   └── AppSettings.swift            # Defaults-based settings
│   ├── Window/
│   │   ├── NotchPanel.swift             # NSPanel subclass (transparent overlay)
│   │   ├── NotchWindowController.swift  # Window positioning + hosting SwiftUI
│   │   └── ScreenObserver.swift         # Monitor display changes
│   ├── Geometry/
│   │   ├── NotchGeometry.swift          # Notch size calculation
│   │   ├── NotchShape.swift             # Animatable notch shape path
│   │   └── NSScreen+Notch.swift         # NSScreen extension for notch detection
│   ├── Events/
│   │   ├── MouseEventMonitor.swift      # Global mouse event handling
│   │   └── HotZoneTracker.swift         # Notch area hover/click detection
│   ├── Models/
│   │   ├── AgentType.swift              # Agent type enum
│   │   ├── SessionStatus.swift          # Unified status enum
│   │   ├── UnifiedSession.swift         # Session state model
│   │   ├── ToolInfo.swift               # Tool execution info
│   │   └── PermissionRequest.swift      # Permission request model
│   ├── Services/
│   │   ├── SocketServer.swift           # NWListener Unix socket server
│   │   ├── SocketConnection.swift       # Single connection handler
│   │   ├── HookInstaller.swift          # Claude Code hook setup
│   │   ├── ClaudeEventParser.swift      # Parse hook JSON → unified events
│   │   ├── SessionManager.swift         # Manage active sessions
│   │   └── TranscriptParser.swift       # Parse JSONL for token usage
│   ├── UI/
│   │   ├── NotchContentView.swift       # Root SwiftUI view (mode switching)
│   │   ├── Compact/
│   │   │   ├── CompactView.swift        # Compact mode layout
│   │   │   └── StatusIndicator.swift    # Animated status dot
│   │   ├── Expanded/
│   │   │   ├── ExpandedView.swift       # Expanded session list
│   │   │   └── SessionCard.swift        # Single session card
│   │   └── FullPanel/
│   │       ├── FullPanelView.swift      # Tab container
│   │       ├── SessionDetailTab.swift   # Tool history + tokens
│   │       ├── PermissionTab.swift      # Approve/deny UI
│   │       └── ToolHistoryRow.swift     # Single tool entry
│   └── Utilities/
│       ├── ToolSummary.swift            # Generate tool summary text
│       ├── TokenFormatter.swift         # Format token counts (12.4k)
│       └── CostCalculator.swift         # Model pricing + cost calc
├── AgentNotchTests/
│   ├── NotchGeometryTests.swift
│   ├── ToolSummaryTests.swift
│   ├── TokenFormatterTests.swift
│   ├── CostCalculatorTests.swift
│   ├── ClaudeEventParserTests.swift
│   ├── SessionManagerTests.swift
│   └── SocketProtocolTests.swift
└── scripts/
    └── claude-hook.py                   # Hook script installed into ~/.claude/hooks/
```

---

## Task 1: Xcode Project + Basic App Shell

**Files:**
- Create: `AgentNotch.xcodeproj` (via xcodebuild)
- Create: `AgentNotch/App/AgentNotchApp.swift`
- Create: `AgentNotch/App/AppDelegate.swift`

- [ ] **Step 1: Create Xcode project**

```bash
cd /Users/y41153/workspace/projects/agent-notch
mkdir -p AgentNotch/App
mkdir -p AgentNotchTests
```

Create `Package.swift` in the project root — we'll use SPM as the build system (no .xcodeproj needed, simpler for CI):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern.git", from: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentNotch",
            dependencies: [
                "Defaults",
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
            ],
            path: "AgentNotch",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AgentNotchTests",
            dependencies: ["AgentNotch"],
            path: "AgentNotchTests"
        ),
    ]
)
```

- [ ] **Step 2: Create the app entry point**

Create `AgentNotch/App/AgentNotchApp.swift`:

```swift
import SwiftUI

@main
struct AgentNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

- [ ] **Step 3: Create AppDelegate with status bar item**

Create `AgentNotch/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agent Notch")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Agent Notch", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }
}
```

- [ ] **Step 4: Create Info.plist for menu bar app**

Create `AgentNotch/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleName</key>
    <string>Agent Notch</string>
    <key>CFBundleIdentifier</key>
    <string>com.agentnotch.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
</dict>
</plist>
```

- [ ] **Step 5: Build and verify**

```bash
cd /Users/y41153/workspace/projects/agent-notch
swift build
```

Expected: Build succeeds. A menu bar app with a sparkle icon.

- [ ] **Step 6: Commit**

```bash
git add Package.swift AgentNotch/ AgentNotchTests/
git commit -m "feat: initial project setup with SPM, AppDelegate, status bar item"
```

---

## Task 2: NSScreen Extension + Notch Geometry

**Files:**
- Create: `AgentNotch/Geometry/NSScreen+Notch.swift`
- Create: `AgentNotch/Geometry/NotchGeometry.swift`
- Create: `AgentNotchTests/NotchGeometryTests.swift`

- [ ] **Step 1: Write failing tests for NotchGeometry**

Create `AgentNotchTests/NotchGeometryTests.swift`:

```swift
import Testing
@testable import AgentNotch

@Suite("NotchGeometry")
struct NotchGeometryTests {
    @Test("notchScreenRect centers horizontally on screen")
    func notchScreenRectCenter() {
        let geo = NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        let rect = geo.notchScreenRect
        #expect(rect.midX == 756.0)
        #expect(rect.width == 200.0)
        #expect(rect.height == 32.0)
        #expect(rect.maxY == 982.0)
    }

    @Test("isPointInNotch returns true for point inside notch with padding")
    func pointInNotch() {
        let geo = NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        let center = CGPoint(x: 756, y: 966)
        #expect(geo.isPointInNotch(center))
    }

    @Test("isPointInNotch returns false for point far from notch")
    func pointOutsideNotch() {
        let geo = NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        let farPoint = CGPoint(x: 100, y: 500)
        #expect(!geo.isPointInNotch(farPoint))
    }

    @Test("windowFrame is wider than notch for compact mode")
    func windowFrameWidth() {
        let geo = NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
        let frame = geo.windowFrame(expandedWidth: 500, expandedHeight: 300, isExpanded: false)
        #expect(frame.width > 200)
        #expect(frame.height >= 32)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter NotchGeometryTests 2>&1
```

Expected: FAIL — `NotchGeometry` not found.

- [ ] **Step 3: Implement NSScreen+Notch**

Create `AgentNotch/Geometry/NSScreen+Notch.swift`:

```swift
import AppKit

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }
        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }
        let notchWidth = frame.width - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    static var builtin: NSScreen? {
        screens.first(where: { $0.isBuiltinDisplay }) ?? NSScreen.main
    }
}
```

- [ ] **Step 4: Implement NotchGeometry**

Create `AgentNotch/Geometry/NotchGeometry.swift`:

```swift
import CoreGraphics

struct NotchGeometry: Sendable {
    let notchSize: CGSize
    let screenFrame: CGRect

    private static let compactPadding: CGFloat = 200

    var notchScreenRect: CGRect {
        CGRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    func isPointInWindow(_ point: CGPoint, isExpanded: Bool, expandedWidth: CGFloat = 500, expandedHeight: CGFloat = 300) -> Bool {
        let frame = windowFrame(expandedWidth: expandedWidth, expandedHeight: expandedHeight, isExpanded: isExpanded)
        return frame.contains(point)
    }

    func windowFrame(expandedWidth: CGFloat, expandedHeight: CGFloat, isExpanded: Bool) -> CGRect {
        if isExpanded {
            return CGRect(
                x: screenFrame.midX - expandedWidth / 2,
                y: screenFrame.maxY - expandedHeight,
                width: expandedWidth,
                height: expandedHeight
            )
        }
        let compactWidth = notchSize.width + Self.compactPadding * 2
        return CGRect(
            x: screenFrame.midX - compactWidth / 2,
            y: screenFrame.maxY - notchSize.height,
            width: compactWidth,
            height: notchSize.height
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter NotchGeometryTests 2>&1
```

Expected: All 4 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentNotch/Geometry/ AgentNotchTests/NotchGeometryTests.swift
git commit -m "feat: add NotchGeometry and NSScreen+Notch for notch detection"
```

---

## Task 3: NotchPanel (NSPanel Subclass)

**Files:**
- Create: `AgentNotch/Window/NotchPanel.swift`
- Create: `AgentNotch/Window/NotchWindowController.swift`

- [ ] **Step 1: Create NotchPanel**

Create `AgentNotch/Window/NotchPanel.swift`:

```swift
import AppKit

final class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        level = .mainMenu + 3
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: Create NotchWindowController**

Create `AgentNotch/Window/NotchWindowController.swift`:

```swift
import AppKit
import SwiftUI

final class NotchWindowController {
    private var panel: NotchPanel?
    private let geometry: NotchGeometry

    init(screen: NSScreen) {
        let notchSize = screen.notchSize
        self.geometry = NotchGeometry(notchSize: notchSize, screenFrame: screen.frame)
    }

    func show(rootView: some View) {
        let frame = geometry.windowFrame(expandedWidth: 500, expandedHeight: 300, isExpanded: false)
        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? frame
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func updateFrame(isExpanded: Bool) {
        guard let panel else { return }
        let frame = geometry.windowFrame(
            expandedWidth: 500,
            expandedHeight: 300,
            isExpanded: isExpanded
        )
        panel.setFrame(frame, display: true, animate: false)
    }

    func setIgnoresMouseEvents(_ ignores: Bool) {
        panel?.ignoresMouseEvents = ignores
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
```

- [ ] **Step 3: Wire up in AppDelegate**

Update `AgentNotch/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupNotchWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agent Notch")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Agent Notch", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupNotchWindow() {
        guard let screen = NSScreen.builtin else { return }
        windowController = NotchWindowController(screen: screen)
        let placeholderView = Text("Agent Notch")
            .foregroundStyle(.white)
            .font(.system(size: 12, weight: .medium))
        windowController?.show(rootView: placeholderView)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
swift build
```

Expected: Builds successfully. Running shows "Agent Notch" text at the notch position.

- [ ] **Step 5: Commit**

```bash
git add AgentNotch/Window/ AgentNotch/App/AppDelegate.swift
git commit -m "feat: add NotchPanel overlay positioned at the notch area"
```

---

## Task 4: NotchShape + Animatable Expand/Collapse

**Files:**
- Create: `AgentNotch/Geometry/NotchShape.swift`
- Create: `AgentNotch/UI/NotchContentView.swift`

- [ ] **Step 1: Create NotchShape**

Create `AgentNotch/Geometry/NotchShape.swift`:

```swift
import SwiftUI

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
```

- [ ] **Step 2: Create NotchContentView with 3-mode switching**

Create `AgentNotch/UI/NotchContentView.swift`:

```swift
import SwiftUI

enum NotchMode {
    case compact
    case expanded
    case fullPanel
}

@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact

    var isExpanded: Bool {
        mode != .compact
    }

    var notchWidth: CGFloat {
        switch mode {
        case .compact: 240
        case .expanded: 480
        case .fullPanel: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: 38
        case .expanded: 300
        case .fullPanel: 500
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact: 6
        case .expanded, .fullPanel: 19
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .expanded, .fullPanel: 24
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            switch mode {
            case .compact: mode = .expanded
            case .expanded: mode = .fullPanel
            case .fullPanel: mode = .compact
            }
        }
    }

    func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
            mode = .compact
        }
    }
}

struct NotchContentView: View {
    @State var viewModel = NotchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                NotchShape(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                )
                .fill(.black)

                Group {
                    switch viewModel.mode {
                    case .compact:
                        compactContent
                    case .expanded:
                        expandedContent
                    case .fullPanel:
                        fullPanelContent
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, viewModel.topCornerRadius + 4)
                .padding(.bottom, viewModel.bottomCornerRadius + 4)
            }
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactContent: some View {
        HStack {
            Text("Agent Notch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.gray)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("No active sessions")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Notch")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text("Full Panel Mode")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 3: Update NotchWindowController to use NotchContentView**

Replace `setupNotchWindow()` in `AgentNotch/App/AppDelegate.swift`:

```swift
    private func setupNotchWindow() {
        guard let screen = NSScreen.builtin else { return }
        windowController = NotchWindowController(screen: screen)
        windowController?.show(rootView: NotchContentView())
    }
```

- [ ] **Step 4: Build and verify visually**

```bash
swift build
```

Expected: Builds. The notch shows a black rounded shape with "Agent Notch" text. (Clicking won't work yet — mouse events are ignored.)

- [ ] **Step 5: Commit**

```bash
git add AgentNotch/Geometry/NotchShape.swift AgentNotch/UI/NotchContentView.swift AgentNotch/App/AppDelegate.swift
git commit -m "feat: add NotchShape with animatable expand/collapse and 3-mode content view"
```

---

## Task 5: Mouse Event Handling (Hover + Click)

**Files:**
- Create: `AgentNotch/Events/MouseEventMonitor.swift`
- Create: `AgentNotch/Events/HotZoneTracker.swift`
- Modify: `AgentNotch/Window/NotchWindowController.swift`
- Modify: `AgentNotch/App/AppDelegate.swift`

- [ ] **Step 1: Create MouseEventMonitor**

Create `AgentNotch/Events/MouseEventMonitor.swift`:

```swift
import AppKit

final class MouseEventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func startMonitoring(
        globalMask: NSEvent.EventTypeMask,
        localMask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { event in
            handler(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { event in
            handler(event)
            return event
        }
    }

    func stopMonitoring() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit {
        stopMonitoring()
    }
}
```

- [ ] **Step 2: Create HotZoneTracker**

Create `AgentNotch/Events/HotZoneTracker.swift`:

```swift
import AppKit

final class HotZoneTracker {
    private let geometry: NotchGeometry
    private let mouseMonitor = MouseEventMonitor()
    var onNotchClicked: (() -> Void)?
    var onClickedOutside: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var isHovering = false

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    func start() {
        mouseMonitor.startMonitoring(
            globalMask: [.leftMouseDown, .mouseMoved],
            localMask: [.leftMouseDown, .mouseMoved]
        ) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    func stop() {
        mouseMonitor.stopMonitoring()
    }

    private func handleEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            if geometry.isPointInNotch(location) {
                onNotchClicked?()
            } else if !geometry.isPointInWindow(location, isExpanded: true, expandedWidth: 650, expandedHeight: 500) {
                onClickedOutside?()
            }
        case .mouseMoved:
            let inNotch = geometry.isPointInNotch(location)
            if inNotch != isHovering {
                isHovering = inNotch
                onHoverChanged?(inNotch)
            }
        default:
            break
        }
    }
}
```

- [ ] **Step 3: Wire up interaction in NotchWindowController**

Replace `AgentNotch/Window/NotchWindowController.swift`:

```swift
import AppKit
import SwiftUI

final class NotchWindowController {
    private var panel: NotchPanel?
    private let geometry: NotchGeometry
    private var hotZone: HotZoneTracker?
    private var viewModel: NotchViewModel?

    init(screen: NSScreen) {
        let notchSize = screen.notchSize
        self.geometry = NotchGeometry(notchSize: notchSize, screenFrame: screen.frame)
    }

    func show(rootView: NotchContentView) {
        let compactFrame = geometry.windowFrame(expandedWidth: 650, expandedHeight: 500, isExpanded: false)
        let fullFrame = geometry.windowFrame(expandedWidth: 650, expandedHeight: 500, isExpanded: true)

        let panel = NotchPanel(
            contentRect: fullFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = panel.contentView?.bounds ?? fullFrame
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)
        panel.setFrame(fullFrame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.viewModel = rootView.viewModel

        setupHotZone()
    }

    private func setupHotZone() {
        let tracker = HotZoneTracker(geometry: geometry)
        tracker.onNotchClicked = { [weak self] in
            self?.viewModel?.toggle()
            self?.panel?.ignoresMouseEvents = self?.viewModel?.isExpanded == true ? false : true
        }
        tracker.onClickedOutside = { [weak self] in
            guard self?.viewModel?.isExpanded == true else { return }
            self?.viewModel?.close()
            self?.panel?.ignoresMouseEvents = true
        }
        tracker.start()
        self.hotZone = tracker
    }

    func close() {
        hotZone?.stop()
        panel?.orderOut(nil)
        panel = nil
    }
}
```

- [ ] **Step 4: Update AppDelegate to pass NotchContentView properly**

Replace `setupNotchWindow()` in `AgentNotch/App/AppDelegate.swift`:

```swift
    private func setupNotchWindow() {
        guard let screen = NSScreen.builtin else { return }
        windowController = NotchWindowController(screen: screen)
        windowController?.show(rootView: NotchContentView())
    }
```

- [ ] **Step 5: Build and test interaction**

```bash
swift build
```

Expected: Clicking the notch area cycles through compact → expanded → fullPanel → compact. Clicking outside collapses back.

- [ ] **Step 6: Commit**

```bash
git add AgentNotch/Events/ AgentNotch/Window/NotchWindowController.swift AgentNotch/App/AppDelegate.swift
git commit -m "feat: add mouse event handling for notch hover and click interactions"
```

---

## Task 6: Unified Event Model

**Files:**
- Create: `AgentNotch/Models/AgentType.swift`
- Create: `AgentNotch/Models/SessionStatus.swift`
- Create: `AgentNotch/Models/ToolInfo.swift`
- Create: `AgentNotch/Models/PermissionRequest.swift`
- Create: `AgentNotch/Models/UnifiedSession.swift`
- Create: `AgentNotch/Utilities/ToolSummary.swift`
- Create: `AgentNotchTests/ToolSummaryTests.swift`

- [ ] **Step 1: Write failing tests for ToolSummary**

Create `AgentNotchTests/ToolSummaryTests.swift`:

```swift
import Testing
@testable import AgentNotch

@Suite("ToolSummary")
struct ToolSummaryTests {
    @Test("Bash tool shows truncated command")
    func bashSummary() {
        let summary = ToolSummary.generate(toolName: "Bash", toolInput: ["command": "npm test --coverage"])
        #expect(summary == "npm test --coverage")
    }

    @Test("Bash tool truncates long command to 30 chars")
    func bashLongSummary() {
        let summary = ToolSummary.generate(toolName: "Bash", toolInput: ["command": "very long command that exceeds thirty characters limit here"])
        #expect(summary.count <= 33) // 30 + "..."
    }

    @Test("Edit tool shows filename")
    func editSummary() {
        let summary = ToolSummary.generate(toolName: "Edit", toolInput: ["file_path": "/Users/me/project/src/main.swift"])
        #expect(summary == "main.swift")
    }

    @Test("Grep tool shows pattern")
    func grepSummary() {
        let summary = ToolSummary.generate(toolName: "Grep", toolInput: ["pattern": "TODO"])
        #expect(summary == "\"TODO\"")
    }

    @Test("WebSearch tool shows truncated query")
    func webSearchSummary() {
        let summary = ToolSummary.generate(toolName: "WebSearch", toolInput: ["query": "React hooks best practices guide"])
        #expect(summary.count <= 23) // 20 + "..."
    }

    @Test("Unknown tool shows tool name")
    func unknownSummary() {
        let summary = ToolSummary.generate(toolName: "CustomTool", toolInput: [:])
        #expect(summary == "CustomTool")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ToolSummaryTests 2>&1
```

Expected: FAIL — `ToolSummary` not found.

- [ ] **Step 3: Create model files**

Create `AgentNotch/Models/AgentType.swift`:

```swift
import SwiftUI

enum AgentType: String, Codable, Sendable, CaseIterable {
    case claudeCode
    case codex
    case geminiCLI
    case custom

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .custom: "Custom"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode: .orange
        case .codex: .blue
        case .geminiCLI: .green
        case .custom: .purple
        }
    }
}
```

Create `AgentNotch/Models/SessionStatus.swift`:

```swift
import SwiftUI

enum SessionStatus: String, Codable, Sendable {
    case starting
    case idle
    case thinking
    case toolRunning
    case permissionWaiting
    case compacting
    case error
    case completed

    var color: Color {
        switch self {
        case .starting: .gray
        case .idle: .gray
        case .thinking: .orange
        case .toolRunning: .green
        case .permissionWaiting: .red
        case .compacting: .purple
        case .error: .red
        case .completed: .blue
        }
    }

    var label: String {
        switch self {
        case .starting: "Starting"
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .toolRunning: "Running tool"
        case .permissionWaiting: "Waiting for approval"
        case .compacting: "Compacting"
        case .error: "Error"
        case .completed: "Completed"
        }
    }
}
```

Create `AgentNotch/Models/ToolInfo.swift`:

```swift
import Foundation

struct ToolInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let input: [String: String]
    let startedAt: Date
    var completedAt: Date?
    var status: ToolStatus
    var durationMs: Int?

    enum ToolStatus: String, Sendable {
        case running
        case succeeded
        case failed
        case denied
    }
}
```

Create `AgentNotch/Models/PermissionRequest.swift`:

```swift
import Foundation

struct PermissionRequest: Identifiable, Sendable {
    let id: String
    let agentType: AgentType
    let sessionId: String
    let toolName: String
    let toolInput: [String: String]
    let timestamp: Date
    let canRespond: Bool
}
```

Create `AgentNotch/Models/UnifiedSession.swift`:

```swift
import Foundation

@Observable
final class UnifiedSession: Identifiable, @unchecked Sendable {
    let id: String
    let agentType: AgentType
    var model: String?
    var cwd: String?
    var status: SessionStatus
    let startedAt: Date
    var endedAt: Date?

    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var totalCachedTokens: Int = 0
    var estimatedCost: Double = 0

    var toolCallCount: Int = 0
    var currentTool: ToolInfo?
    var recentTools: [ToolInfo] = []

    var pendingPermissions: [PermissionRequest] = []

    var pid: Int?
    var tty: String?
    var transcriptPath: String?

    var elapsedTime: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    init(id: String, agentType: AgentType, status: SessionStatus = .starting) {
        self.id = id
        self.agentType = agentType
        self.status = status
        self.startedAt = Date()
    }
}
```

- [ ] **Step 4: Create ToolSummary**

Create `AgentNotch/Utilities/ToolSummary.swift`:

```swift
import Foundation

enum ToolSummary {
    static func generate(toolName: String, toolInput: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            let cmd = toolInput["command"] as? String ?? ""
            return truncate(cmd, maxLength: 30)
        case "Edit", "Write", "Read":
            let path = toolInput["file_path"] as? String ?? ""
            return (path as NSString).lastPathComponent
        case "Grep":
            let pattern = toolInput["pattern"] as? String ?? ""
            return "\"\(pattern)\""
        case "Glob":
            let pattern = toolInput["pattern"] as? String ?? ""
            return pattern
        case "WebSearch":
            let query = toolInput["query"] as? String ?? ""
            return truncate(query, maxLength: 20)
        case "WebFetch":
            let url = toolInput["url"] as? String ?? ""
            return extractDomain(from: url)
        case "Agent":
            return toolInput["subagent_type"] as? String ?? "Agent"
        default:
            if toolName.hasPrefix("mcp__") {
                let parts = toolName.dropFirst(5).split(separator: "__", maxSplits: 1)
                if parts.count == 2 {
                    return "\(parts[0]):\(parts[1])"
                }
            }
            return toolName
        }
    }

    private static func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength { return string }
        return String(string.prefix(maxLength)) + "..."
    }

    private static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        return host
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter ToolSummaryTests 2>&1
```

Expected: All 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentNotch/Models/ AgentNotch/Utilities/ToolSummary.swift AgentNotchTests/ToolSummaryTests.swift
git commit -m "feat: add unified event model (AgentType, SessionStatus, UnifiedSession, ToolInfo)"
```

---

## Task 7: Token Formatter + Cost Calculator

**Files:**
- Create: `AgentNotch/Utilities/TokenFormatter.swift`
- Create: `AgentNotch/Utilities/CostCalculator.swift`
- Create: `AgentNotchTests/TokenFormatterTests.swift`
- Create: `AgentNotchTests/CostCalculatorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `AgentNotchTests/TokenFormatterTests.swift`:

```swift
import Testing
@testable import AgentNotch

@Suite("TokenFormatter")
struct TokenFormatterTests {
    @Test("formats small numbers as-is")
    func smallNumber() {
        #expect(TokenFormatter.format(500) == "500")
    }

    @Test("formats thousands with k suffix")
    func thousands() {
        #expect(TokenFormatter.format(12432) == "12.4k")
    }

    @Test("formats millions with M suffix")
    func millions() {
        #expect(TokenFormatter.format(1_500_000) == "1.5M")
    }

    @Test("formats zero")
    func zero() {
        #expect(TokenFormatter.format(0) == "0")
    }
}
```

Create `AgentNotchTests/CostCalculatorTests.swift`:

```swift
import Testing
@testable import AgentNotch

@Suite("CostCalculator")
struct CostCalculatorTests {
    @Test("calculates cost for claude-opus-4-6")
    func opusCost() {
        let cost = CostCalculator.estimateCost(
            model: "claude-opus-4-6",
            inputTokens: 10_000,
            outputTokens: 1_000,
            cachedTokens: 5_000
        )
        // input: 10000 * 15 / 1_000_000 = 0.15
        // output: 1000 * 75 / 1_000_000 = 0.075
        // cached: 5000 * 1.5 / 1_000_000 = 0.0075
        // total = 0.2325
        #expect(abs(cost - 0.2325) < 0.001)
    }

    @Test("returns 0 for unknown model")
    func unknownModel() {
        let cost = CostCalculator.estimateCost(
            model: "unknown-model",
            inputTokens: 1000,
            outputTokens: 500,
            cachedTokens: 0
        )
        #expect(cost == 0)
    }

    @Test("formats cost as currency")
    func formatCost() {
        #expect(CostCalculator.formatCost(0.2325) == "$0.23")
        #expect(CostCalculator.formatCost(4.5) == "$4.50")
        #expect(CostCalculator.formatCost(0.001) == "<$0.01")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "TokenFormatterTests|CostCalculatorTests" 2>&1
```

Expected: FAIL — modules not found.

- [ ] **Step 3: Implement TokenFormatter**

Create `AgentNotch/Utilities/TokenFormatter.swift`:

```swift
enum TokenFormatter {
    static func format(_ count: Int) -> String {
        if count == 0 { return "0" }
        if count < 1_000 { return "\(count)" }
        if count < 1_000_000 {
            let k = Double(count) / 1_000
            return k.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(k))k"
                : String(format: "%.1fk", k)
        }
        let m = Double(count) / 1_000_000
        return String(format: "%.1fM", m)
    }
}
```

- [ ] **Step 4: Implement CostCalculator**

Create `AgentNotch/Utilities/CostCalculator.swift`:

```swift
struct ModelPricing {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cachedPerMillion: Double
}

enum CostCalculator {
    static let pricingTable: [String: ModelPricing] = [
        // Anthropic
        "claude-opus-4-6": ModelPricing(inputPerMillion: 15.0, outputPerMillion: 75.0, cachedPerMillion: 1.5),
        "claude-sonnet-4-6": ModelPricing(inputPerMillion: 3.0, outputPerMillion: 15.0, cachedPerMillion: 0.3),
        "claude-haiku-4-5": ModelPricing(inputPerMillion: 0.8, outputPerMillion: 4.0, cachedPerMillion: 0.08),
        // OpenAI
        "o3": ModelPricing(inputPerMillion: 10.0, outputPerMillion: 40.0, cachedPerMillion: 2.5),
        "o4-mini": ModelPricing(inputPerMillion: 1.1, outputPerMillion: 4.4, cachedPerMillion: 0.275),
        "gpt-4.1": ModelPricing(inputPerMillion: 2.0, outputPerMillion: 8.0, cachedPerMillion: 0.5),
        // Google
        "gemini-2.5-pro": ModelPricing(inputPerMillion: 1.25, outputPerMillion: 10.0, cachedPerMillion: 0.315),
        "gemini-2.5-flash": ModelPricing(inputPerMillion: 0.15, outputPerMillion: 0.6, cachedPerMillion: 0.0375),
    ]

    static func estimateCost(model: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int) -> Double {
        guard let pricing = pricingTable[model] else { return 0 }
        let input = Double(inputTokens) * pricing.inputPerMillion / 1_000_000
        let output = Double(outputTokens) * pricing.outputPerMillion / 1_000_000
        let cached = Double(cachedTokens) * pricing.cachedPerMillion / 1_000_000
        return input + output + cached
    }

    static func formatCost(_ cost: Double) -> String {
        if cost == 0 { return "$0.00" }
        if cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter "TokenFormatterTests|CostCalculatorTests" 2>&1
```

Expected: All 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentNotch/Utilities/TokenFormatter.swift AgentNotch/Utilities/CostCalculator.swift AgentNotchTests/TokenFormatterTests.swift AgentNotchTests/CostCalculatorTests.swift
git commit -m "feat: add TokenFormatter and CostCalculator with pricing table"
```

---

## Task 8: SessionManager

**Files:**
- Create: `AgentNotch/Services/SessionManager.swift`
- Create: `AgentNotchTests/SessionManagerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `AgentNotchTests/SessionManagerTests.swift`:

```swift
import Testing
@testable import AgentNotch

@Suite("SessionManager")
struct SessionManagerTests {
    @Test("creates new session")
    func createSession() {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "abc123", agentType: .claudeCode)
        #expect(session.id == "abc123")
        #expect(session.agentType == .claudeCode)
        #expect(session.status == .starting)
        #expect(manager.activeSessions.count == 1)
    }

    @Test("returns existing session for same id")
    func existingSession() {
        let manager = SessionManager()
        let s1 = manager.getOrCreateSession(id: "abc123", agentType: .claudeCode)
        s1.status = .thinking
        let s2 = manager.getOrCreateSession(id: "abc123", agentType: .claudeCode)
        #expect(s2.status == .thinking)
        #expect(manager.activeSessions.count == 1)
    }

    @Test("removes completed session after delay")
    func removeCompleted() async throws {
        let manager = SessionManager()
        let session = manager.getOrCreateSession(id: "abc123", agentType: .claudeCode)
        session.status = .completed
        session.endedAt = Date()
        manager.cleanupCompleted(olderThan: 0)
        #expect(manager.activeSessions.isEmpty)
    }

    @Test("tracks multiple sessions")
    func multipleSessions() {
        let manager = SessionManager()
        _ = manager.getOrCreateSession(id: "s1", agentType: .claudeCode)
        _ = manager.getOrCreateSession(id: "s2", agentType: .codex)
        #expect(manager.activeSessions.count == 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SessionManagerTests 2>&1
```

Expected: FAIL — `SessionManager` not found.

- [ ] **Step 3: Implement SessionManager**

Create `AgentNotch/Services/SessionManager.swift`:

```swift
import Foundation

@Observable
final class SessionManager: @unchecked Sendable {
    private var sessions: [String: UnifiedSession] = [:]

    var activeSessions: [UnifiedSession] {
        sessions.values
            .filter { $0.status != .completed }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var allSessions: [UnifiedSession] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    var pendingPermissionCount: Int {
        sessions.values.reduce(0) { $0 + $1.pendingPermissions.count }
    }

    func getOrCreateSession(id: String, agentType: AgentType) -> UnifiedSession {
        if let existing = sessions[id] { return existing }
        let session = UnifiedSession(id: id, agentType: agentType)
        sessions[id] = session
        return session
    }

    func session(for id: String) -> UnifiedSession? {
        sessions[id]
    }

    func cleanupCompleted(olderThan seconds: TimeInterval = 300) {
        let cutoff = Date().addingTimeInterval(-seconds)
        sessions = sessions.filter { _, session in
            if session.status == .completed, let endedAt = session.endedAt, endedAt < cutoff {
                return false
            }
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter SessionManagerTests 2>&1
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AgentNotch/Services/SessionManager.swift AgentNotchTests/SessionManagerTests.swift
git commit -m "feat: add SessionManager for tracking active agent sessions"
```

---

## Task 9: Unix Socket Server (Network.framework)

**Files:**
- Create: `AgentNotch/Services/SocketServer.swift`
- Create: `AgentNotch/Services/SocketConnection.swift`
- Create: `AgentNotchTests/SocketProtocolTests.swift`

- [ ] **Step 1: Write failing tests for the wire protocol**

Create `AgentNotchTests/SocketProtocolTests.swift`:

```swift
import Testing
import Foundation
@testable import AgentNotch

@Suite("SocketProtocol")
struct SocketProtocolTests {
    @Test("encodes message with 4-byte length prefix")
    func encodeMessage() throws {
        let message = ["event": "test"]
        let data = try SocketProtocol.encode(message)
        // First 4 bytes = UInt32 length of JSON payload
        let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let payload = data.dropFirst(4)
        #expect(Int(length) == payload.count)
        let decoded = try JSONSerialization.jsonObject(with: Data(payload)) as? [String: String]
        #expect(decoded?["event"] == "test")
    }

    @Test("decodes length-prefixed message")
    func decodeMessage() throws {
        let json = #"{"event":"hello"}"#
        let jsonData = json.data(using: .utf8)!
        var data = Data()
        var length = UInt32(jsonData.count)
        data.append(Data(bytes: &length, count: 4))
        data.append(jsonData)

        let (decoded, consumed) = try SocketProtocol.decode(data)
        #expect(decoded["event"] as? String == "hello")
        #expect(consumed == 4 + jsonData.count)
    }

    @Test("decode returns nil for incomplete data")
    func incompleteData() throws {
        let data = Data([0x0A, 0x00]) // only 2 bytes, need at least 4
        let result = try? SocketProtocol.decode(data)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SocketProtocolTests 2>&1
```

Expected: FAIL — `SocketProtocol` not found.

- [ ] **Step 3: Implement SocketProtocol helper**

Add to top of `AgentNotch/Services/SocketConnection.swift`:

Create `AgentNotch/Services/SocketConnection.swift`:

```swift
import Foundation
import Network

enum SocketProtocol {
    static func encode(_ object: Any) throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: object)
        var length = UInt32(jsonData.count)
        var data = Data(bytes: &length, count: 4)
        data.append(jsonData)
        return data
    }

    static func decode(_ data: Data) throws -> (message: [String: Any], bytesConsumed: Int)? {
        guard data.count >= 4 else { return nil }
        let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) }
        let totalNeeded = 4 + Int(length)
        guard data.count >= totalNeeded else { return nil }
        let jsonData = data[4..<totalNeeded]
        guard let dict = try JSONSerialization.jsonObject(with: Data(jsonData)) as? [String: Any] else {
            throw SocketError.invalidJSON
        }
        return (dict, totalNeeded)
    }
}

enum SocketError: Error {
    case invalidJSON
    case connectionFailed
}

final class SocketConnection: Sendable {
    let connection: NWConnection
    let onMessage: @Sendable ([String: Any]) -> [String: Any]?

    init(connection: NWConnection, onMessage: @escaping @Sendable ([String: Any]) -> [String: Any]?) {
        self.connection = connection
        self.onMessage = onMessage
    }

    func start() {
        connection.start(queue: .global())
        receiveLoop()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self, let data = content else {
                self?.connection.cancel()
                return
            }
            if let (message, _) = try? SocketProtocol.decode(data) {
                if let response = self.onMessage(message) {
                    if let responseData = try? SocketProtocol.encode(response) {
                        self.connection.send(content: responseData, completion: .contentProcessed { _ in })
                    }
                }
            }
            if !isComplete {
                self.receiveLoop()
            } else {
                self.connection.cancel()
            }
        }
    }
}
```

- [ ] **Step 4: Implement SocketServer**

Create `AgentNotch/Services/SocketServer.swift`:

```swift
import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.agentnotch", category: "Socket")

final class SocketServer: @unchecked Sendable {
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: SocketConnection] = [:]
    let socketPath: String
    let onMessage: @Sendable ([String: Any]) -> [String: Any]?

    init(onMessage: @escaping @Sendable ([String: Any]) -> [String: Any]?) {
        let username = NSUserName()
        self.socketPath = "/tmp/agent-notch-\(username).sock"
        self.onMessage = onMessage
    }

    func start() throws {
        // Clean up stale socket
        try? FileManager.default.removeItem(atPath: socketPath)

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .unix(path: socketPath)
        let listener = try NWListener(using: params)

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("Socket server listening at \(self.socketPath)")
            case .failed(let error):
                logger.error("Socket server failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global())
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: socketPath)
        connections.removeAll()
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let conn = SocketConnection(connection: nwConnection, onMessage: onMessage)
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        conn.start()
        logger.debug("New connection accepted")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter SocketProtocolTests 2>&1
```

Expected: All 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add AgentNotch/Services/SocketServer.swift AgentNotch/Services/SocketConnection.swift AgentNotchTests/SocketProtocolTests.swift
git commit -m "feat: add Unix socket server using Network.framework with length-prefixed JSON protocol"
```

---

## Task 10: Claude Code Event Parser

**Files:**
- Create: `AgentNotch/Services/ClaudeEventParser.swift`
- Create: `AgentNotchTests/ClaudeEventParserTests.swift`

- [ ] **Step 1: Write failing tests**

Create `AgentNotchTests/ClaudeEventParserTests.swift`:

```swift
import Testing
import Foundation
@testable import AgentNotch

@Suite("ClaudeEventParser")
struct ClaudeEventParserTests {
    @Test("parses SessionStart event")
    func sessionStart() {
        let json: [String: Any] = [
            "hook_event_name": "SessionStart",
            "session_id": "abc123",
            "model": "claude-opus-4-6",
            "cwd": "/Users/me/project",
            "source": "startup",
            "transcript_path": "/Users/me/.claude/sessions/abc123.jsonl"
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .sessionStarted(let info) = event else {
            Issue.record("Expected sessionStarted")
            return
        }
        #expect(info.sessionId == "abc123")
        #expect(info.model == "claude-opus-4-6")
    }

    @Test("parses PreToolUse event")
    func preToolUse() {
        let json: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "abc123",
            "tool_name": "Edit",
            "tool_input": ["file_path": "/src/main.swift", "old_string": "x", "new_string": "y"],
            "tool_use_id": "tool_001",
            "transcript_path": ""
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .toolStarted(let info) = event else {
            Issue.record("Expected toolStarted")
            return
        }
        #expect(info.toolName == "Edit")
        #expect(info.toolUseId == "tool_001")
        #expect(info.summary == "main.swift")
    }

    @Test("parses PermissionRequest event")
    func permissionRequest() {
        let json: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": "abc123",
            "tool_name": "Bash",
            "tool_input": ["command": "rm -rf node_modules"],
            "transcript_path": ""
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .permissionRequested(let req) = event else {
            Issue.record("Expected permissionRequested")
            return
        }
        #expect(req.toolName == "Bash")
    }

    @Test("parses Stop event")
    func stopEvent() {
        let json: [String: Any] = [
            "hook_event_name": "Stop",
            "session_id": "abc123",
            "transcript_path": "/Users/me/.claude/sessions/abc123.jsonl"
        ]
        let event = ClaudeEventParser.parse(json)
        guard case .sessionIdle(let sessionId) = event else {
            Issue.record("Expected sessionIdle")
            return
        }
        #expect(sessionId == "abc123")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ClaudeEventParserTests 2>&1
```

Expected: FAIL — `ClaudeEventParser` not found.

- [ ] **Step 3: Implement ClaudeEventParser**

Create `AgentNotch/Services/ClaudeEventParser.swift`:

```swift
import Foundation

enum ClaudeEvent {
    struct SessionInfo {
        let sessionId: String
        let model: String?
        let cwd: String?
        let transcriptPath: String?
        let source: String?
    }

    struct ToolStartInfo {
        let sessionId: String
        let toolName: String
        let toolUseId: String
        let toolInput: [String: Any]
        let summary: String
    }

    struct ToolEndInfo {
        let sessionId: String
        let toolUseId: String
        let toolName: String
    }

    struct ToolFailInfo {
        let sessionId: String
        let toolUseId: String
        let error: String
    }

    struct PermissionInfo {
        let sessionId: String
        let toolName: String
        let toolInput: [String: Any]
    }

    case sessionStarted(SessionInfo)
    case userPrompt(sessionId: String)
    case toolStarted(ToolStartInfo)
    case toolCompleted(ToolEndInfo)
    case toolFailed(ToolFailInfo)
    case permissionRequested(PermissionInfo)
    case notification(sessionId: String, type: String, message: String)
    case sessionIdle(String)
    case sessionEnded(String)
    case subagentStopped(sessionId: String)
    case compacting(sessionId: String)
    case unknown
}

enum ClaudeEventParser {
    static func parse(_ json: [String: Any]) -> ClaudeEvent {
        guard let eventName = json["hook_event_name"] as? String,
              let sessionId = json["session_id"] as? String else {
            return .unknown
        }

        switch eventName {
        case "SessionStart":
            return .sessionStarted(ClaudeEvent.SessionInfo(
                sessionId: sessionId,
                model: json["model"] as? String,
                cwd: json["cwd"] as? String,
                transcriptPath: json["transcript_path"] as? String,
                source: json["source"] as? String
            ))

        case "UserPromptSubmit":
            return .userPrompt(sessionId: sessionId)

        case "PreToolUse":
            let toolName = json["tool_name"] as? String ?? "Unknown"
            let toolInput = json["tool_input"] as? [String: Any] ?? [:]
            let toolUseId = json["tool_use_id"] as? String ?? UUID().uuidString
            let summary = ToolSummary.generate(toolName: toolName, toolInput: toolInput)
            return .toolStarted(ClaudeEvent.ToolStartInfo(
                sessionId: sessionId,
                toolName: toolName,
                toolUseId: toolUseId,
                toolInput: toolInput,
                summary: summary
            ))

        case "PostToolUse":
            return .toolCompleted(ClaudeEvent.ToolEndInfo(
                sessionId: sessionId,
                toolUseId: json["tool_use_id"] as? String ?? "",
                toolName: json["tool_name"] as? String ?? ""
            ))

        case "PostToolUseFailure":
            return .toolFailed(ClaudeEvent.ToolFailInfo(
                sessionId: sessionId,
                toolUseId: json["tool_use_id"] as? String ?? "",
                error: json["error"] as? String ?? "Unknown error"
            ))

        case "PermissionRequest":
            return .permissionRequested(ClaudeEvent.PermissionInfo(
                sessionId: sessionId,
                toolName: json["tool_name"] as? String ?? "Unknown",
                toolInput: json["tool_input"] as? [String: Any] ?? [:]
            ))

        case "Notification":
            return .notification(
                sessionId: sessionId,
                type: json["notification_type"] as? String ?? "",
                message: json["message"] as? String ?? ""
            )

        case "Stop", "SubagentStop":
            return eventName == "Stop"
                ? .sessionIdle(sessionId)
                : .subagentStopped(sessionId: sessionId)

        case "SessionEnd":
            return .sessionEnded(sessionId)

        case "PreCompact":
            return .compacting(sessionId: sessionId)

        default:
            return .unknown
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter ClaudeEventParserTests 2>&1
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AgentNotch/Services/ClaudeEventParser.swift AgentNotchTests/ClaudeEventParserTests.swift
git commit -m "feat: add ClaudeEventParser to map Claude Code hook events to unified model"
```

---

## Task 11: Hook Installer + Hook Script

**Files:**
- Create: `AgentNotch/Services/HookInstaller.swift`
- Create: `scripts/claude-hook.py`

- [ ] **Step 1: Create the hook Python script**

Create `scripts/claude-hook.py`:

```python
#!/usr/bin/env python3
"""
Agent Notch hook script for Claude Code.
Reads JSON from stdin and forwards it to the Agent Notch Unix socket.
Adds PID and TTY information.
"""
import json
import os
import socket
import struct
import subprocess
import sys

SOCKET_PATH = f"/tmp/agent-notch-{os.environ.get('USER', 'unknown')}.sock"

def get_tty():
    try:
        ppid = os.getppid()
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True, text=True, timeout=2
        )
        return result.stdout.strip()
    except Exception:
        return ""

def send_to_socket(data):
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(5)
        sock.connect(SOCKET_PATH)

        payload = json.dumps(data).encode("utf-8")
        header = struct.pack("<I", len(payload))
        sock.sendall(header + payload)

        # Read response (4-byte length + JSON)
        resp_header = sock.recv(4)
        if len(resp_header) == 4:
            resp_len = struct.unpack("<I", resp_header)[0]
            resp_data = sock.recv(resp_len)
            response = json.loads(resp_data)
            sock.close()
            return response
        sock.close()
    except (ConnectionRefusedError, FileNotFoundError):
        pass  # Agent Notch not running
    except Exception:
        pass
    return None

def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    input_data["_pid"] = os.getppid()
    input_data["_tty"] = get_tty()

    response = send_to_socket(input_data)

    if response:
        json.dump(response, sys.stdout)
    else:
        json.dump({}, sys.stdout)

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Create HookInstaller**

Create `AgentNotch/Services/HookInstaller.swift`:

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.agentnotch", category: "HookInstaller")

enum HookInstaller {
    private static let hookVersion = "1"
    private static let claudeHooksDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/hooks")

    private static let hookEvents: [(event: String, matchers: [String]?, timeout: Int?)] = [
        ("SessionStart", nil, nil),
        ("UserPromptSubmit", nil, nil),
        ("PreToolUse", ["*"], nil),
        ("PostToolUse", ["*"], nil),
        ("PostToolUseFailure", ["*"], nil),
        ("PermissionRequest", ["*"], 86400),
        ("Notification", ["*"], nil),
        ("Stop", nil, nil),
        ("SubagentStop", nil, nil),
        ("SessionEnd", nil, nil),
        ("PreCompact", ["auto", "manual"], nil),
    ]

    static func installIfNeeded() {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let scriptPath = bundledHookScriptPath()

        for (event, matchers, timeout) in hookEvents {
            var hookEntry: [String: Any] = [
                "type": "command",
                "command": "python3 \(scriptPath)",
            ]
            if let timeout { hookEntry["timeout"] = timeout }

            var matcherEntry: [String: Any] = ["hooks": [hookEntry]]
            if let matchers {
                matcherEntry["matcher"] = matchers.count == 1 ? matchers[0] as Any : matchers as Any
            }

            hooks[event] = [matcherEntry]
        }

        settings["hooks"] = hooks
        settings["_agentNotchHookVersion"] = hookVersion

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settingsPath, options: .atomic)
            logger.info("Claude Code hooks installed/updated")
        }
    }

    static func isInstalled() -> Bool {
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return json["_agentNotchHookVersion"] as? String == hookVersion
    }

    private static func bundledHookScriptPath() -> String {
        // For development: use the script from the repo
        let devPath = Bundle.main.bundlePath + "/Contents/Resources/claude-hook.py"
        if FileManager.default.fileExists(atPath: devPath) { return devPath }
        // Fallback: home directory
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-notch/claude-hook.py").path
        if !FileManager.default.fileExists(atPath: homePath) {
            installHookScript(to: homePath)
        }
        return homePath
    }

    private static func installHookScript(to path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let sourceURL = Bundle.main.url(forResource: "claude-hook", withExtension: "py") else {
            logger.error("Hook script not found in bundle")
            return
        }
        try? FileManager.default.copyItem(at: sourceURL, to: URL(fileURLWithPath: path))
        // Make executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }
}
```

- [ ] **Step 3: Create Resources directory and copy script**

```bash
mkdir -p /Users/y41153/workspace/projects/agent-notch/AgentNotch/Resources
cp /Users/y41153/workspace/projects/agent-notch/scripts/claude-hook.py /Users/y41153/workspace/projects/agent-notch/AgentNotch/Resources/claude-hook.py
chmod +x /Users/y41153/workspace/projects/agent-notch/scripts/claude-hook.py
```

- [ ] **Step 4: Build and verify**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 5: Commit**

```bash
git add scripts/claude-hook.py AgentNotch/Services/HookInstaller.swift AgentNotch/Resources/claude-hook.py
git commit -m "feat: add Claude Code hook installer and forwarding script"
```

---

## Task 12: Transcript Parser (Token Extraction)

**Files:**
- Create: `AgentNotch/Services/TranscriptParser.swift`

- [ ] **Step 1: Implement TranscriptParser**

Create `AgentNotch/Services/TranscriptParser.swift`:

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.agentnotch", category: "Transcript")

struct TokenUsage: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int { inputTokens + outputTokens }
    var cachedTokens: Int { cacheCreationTokens + cacheReadTokens }
}

enum TranscriptParser {
    static func parseLatestUsage(at path: String) -> TokenUsage? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        var totalUsage = TokenUsage()
        let lines = content.components(separatedBy: .newlines)

        for line in lines.reversed() {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let usage = json["usage"] as? [String: Any] else {
                continue
            }

            totalUsage.inputTokens = usage["input_tokens"] as? Int ?? 0
            totalUsage.outputTokens = usage["output_tokens"] as? Int ?? 0
            totalUsage.cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
            totalUsage.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
            return totalUsage
        }

        return nil
    }

    static func parseCumulativeUsage(at path: String) -> TokenUsage {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return TokenUsage() }
        guard let content = String(data: data, encoding: .utf8) else { return TokenUsage() }

        var total = TokenUsage()
        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let usage = json["usage"] as? [String: Any] else {
                continue
            }
            total.inputTokens += usage["input_tokens"] as? Int ?? 0
            total.outputTokens += usage["output_tokens"] as? Int ?? 0
            total.cacheCreationTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            total.cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
        }
        return total
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add AgentNotch/Services/TranscriptParser.swift
git commit -m "feat: add TranscriptParser to extract token usage from Claude Code JSONL transcripts"
```

---

## Task 13: Wire Everything Together — Event Processing Pipeline

**Files:**
- Modify: `AgentNotch/App/AppDelegate.swift`
- Modify: `AgentNotch/UI/NotchContentView.swift`

- [ ] **Step 1: Update AppDelegate to start services and pass SessionManager**

Replace `AgentNotch/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.agentnotch", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NotchWindowController?
    private var socketServer: SocketServer?
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startSocketServer()
        installHooksIfNeeded()
        setupNotchWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Agent Notch")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Agent Notch", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func startSocketServer() {
        socketServer = SocketServer { [weak self] message in
            self?.handleHookMessage(message)
        }
        do {
            try socketServer?.start()
            logger.info("Socket server started")
        } catch {
            logger.error("Failed to start socket server: \(error)")
        }
    }

    private func installHooksIfNeeded() {
        if !HookInstaller.isInstalled() {
            HookInstaller.installIfNeeded()
        }
    }

    private func setupNotchWindow() {
        guard let screen = NSScreen.builtin else { return }
        windowController = NotchWindowController(screen: screen)
        windowController?.show(rootView: NotchContentView(sessionManager: sessionManager))
    }

    private func handleHookMessage(_ message: [String: Any]) -> [String: Any]? {
        let event = ClaudeEventParser.parse(message)
        let pid = message["_pid"] as? Int
        let tty = message["_tty"] as? String

        DispatchQueue.main.async { [weak self] in
            self?.processEvent(event, pid: pid, tty: tty)
        }

        // For PermissionRequest, we need to wait for user response
        // For now, return empty (auto-defer)
        return [:]
    }

    private func processEvent(_ event: ClaudeEvent, pid: Int?, tty: String?) {
        switch event {
        case .sessionStarted(let info):
            let session = sessionManager.getOrCreateSession(id: info.sessionId, agentType: .claudeCode)
            session.model = info.model
            session.cwd = info.cwd
            session.transcriptPath = info.transcriptPath
            session.pid = pid
            session.tty = tty
            session.status = .idle

        case .userPrompt(let sessionId):
            sessionManager.session(for: sessionId)?.status = .thinking

        case .toolStarted(let info):
            let session = sessionManager.session(for: info.sessionId)
            session?.status = .toolRunning
            let tool = ToolInfo(
                id: info.toolUseId,
                name: info.toolName,
                summary: info.summary,
                input: info.toolInput.compactMapValues { "\($0)" },
                startedAt: Date(),
                status: .running
            )
            session?.currentTool = tool
            session?.toolCallCount += 1

        case .toolCompleted(let info):
            let session = sessionManager.session(for: info.sessionId)
            session?.currentTool?.status = .succeeded
            session?.currentTool?.completedAt = Date()
            if let tool = session?.currentTool {
                session?.recentTools.insert(tool, at: 0)
                if (session?.recentTools.count ?? 0) > 50 {
                    session?.recentTools.removeLast()
                }
            }
            session?.currentTool = nil
            session?.status = .thinking

        case .toolFailed(let info):
            let session = sessionManager.session(for: info.sessionId)
            session?.currentTool?.status = .failed
            session?.currentTool?.completedAt = Date()
            if let tool = session?.currentTool {
                session?.recentTools.insert(tool, at: 0)
            }
            session?.currentTool = nil
            session?.status = .thinking

        case .permissionRequested(let info):
            let session = sessionManager.session(for: info.sessionId)
            session?.status = .permissionWaiting
            let req = PermissionRequest(
                id: UUID().uuidString,
                agentType: .claudeCode,
                sessionId: info.sessionId,
                toolName: info.toolName,
                toolInput: info.toolInput.compactMapValues { "\($0)" },
                timestamp: Date(),
                canRespond: true
            )
            session?.pendingPermissions.append(req)

        case .notification(let sessionId, let type, _):
            if type == "idle_prompt" {
                sessionManager.session(for: sessionId)?.status = .idle
            }

        case .sessionIdle(let sessionId):
            let session = sessionManager.session(for: sessionId)
            session?.status = .idle
            // Update token usage from transcript
            if let path = session?.transcriptPath {
                let usage = TranscriptParser.parseCumulativeUsage(at: path)
                session?.totalInputTokens = usage.inputTokens
                session?.totalOutputTokens = usage.outputTokens
                session?.totalCachedTokens = usage.cachedTokens
                if let model = session?.model {
                    session?.estimatedCost = CostCalculator.estimateCost(
                        model: model,
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        cachedTokens: usage.cachedTokens
                    )
                }
            }

        case .sessionEnded(let sessionId):
            let session = sessionManager.session(for: sessionId)
            session?.status = .completed
            session?.endedAt = Date()

        case .compacting(let sessionId):
            sessionManager.session(for: sessionId)?.status = .compacting

        case .subagentStopped:
            break

        case .unknown:
            break
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }
}
```

- [ ] **Step 2: Update NotchContentView to accept SessionManager**

Replace `AgentNotch/UI/NotchContentView.swift` — update the struct to receive `sessionManager`:

```swift
import SwiftUI

enum NotchMode {
    case compact
    case expanded
    case fullPanel
}

@Observable
final class NotchViewModel {
    var mode: NotchMode = .compact

    var isExpanded: Bool { mode != .compact }

    var notchWidth: CGFloat {
        switch mode {
        case .compact: 240
        case .expanded: 480
        case .fullPanel: 650
        }
    }

    var notchHeight: CGFloat {
        switch mode {
        case .compact: 38
        case .expanded: 300
        case .fullPanel: 500
        }
    }

    var topCornerRadius: CGFloat {
        switch mode {
        case .compact: 6
        case .expanded, .fullPanel: 19
        }
    }

    var bottomCornerRadius: CGFloat {
        switch mode {
        case .compact: 14
        case .expanded, .fullPanel: 24
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            switch mode {
            case .compact: mode = .expanded
            case .expanded: mode = .fullPanel
            case .fullPanel: mode = .compact
            }
        }
    }

    func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
            mode = .compact
        }
    }
}

struct NotchContentView: View {
    @State var viewModel = NotchViewModel()
    var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                NotchShape(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                )
                .fill(.black)

                Group {
                    switch viewModel.mode {
                    case .compact:
                        compactContent
                    case .expanded:
                        expandedContent
                    case .fullPanel:
                        fullPanelContent
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, viewModel.topCornerRadius + 4)
                .padding(.bottom, viewModel.bottomCornerRadius + 4)
            }
            .frame(width: viewModel.notchWidth, height: viewModel.notchHeight)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: viewModel.mode)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactContent: some View {
        HStack(spacing: 8) {
            ForEach(sessionManager.activeSessions) { session in
                HStack(spacing: 4) {
                    Circle()
                        .fill(session.status.color)
                        .frame(width: 6, height: 6)
                    Text(session.currentTool?.summary ?? session.status.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            if sessionManager.activeSessions.isEmpty {
                Text("Agent Notch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sessionManager.activeSessions) { session in
                sessionRow(session)
            }
            if sessionManager.activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRow(_ session: UnifiedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(session.agentType.color).frame(width: 8, height: 8)
                Text(session.agentType.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                if let model = session.model {
                    Text(model).font(.system(size: 10)).foregroundStyle(.gray)
                }
                Spacer()
                Text(formatDuration(session.elapsedTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            if let tool = session.currentTool {
                Text("\(tool.name): \(tool.summary)")
                    .font(.system(size: 11))
                    .foregroundStyle(session.status.color)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Text("\(TokenFormatter.format(session.totalInputTokens)) in / \(TokenFormatter.format(session.totalOutputTokens)) out")
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                Text(CostCalculator.formatCost(session.estimatedCost))
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fullPanelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Notch")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)

            ForEach(sessionManager.activeSessions) { session in
                sessionRow(session)
                if !session.recentTools.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(session.recentTools.prefix(10)) { tool in
                            HStack(spacing: 4) {
                                Image(systemName: tool.status == .succeeded ? "checkmark.circle" : "xmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(tool.status == .succeeded ? .green : .red)
                                Text("\(tool.name): \(tool.summary)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }
}
```

- [ ] **Step 3: Update NotchWindowController.show signature**

In `AgentNotch/Window/NotchWindowController.swift`, the `show` method already accepts `NotchContentView`, no change needed since the new `NotchContentView` has the same type.

- [ ] **Step 4: Build and verify**

```bash
swift build
```

Expected: Builds successfully. The app now shows live Claude Code session data when Claude Code is running with hooks installed.

- [ ] **Step 5: Commit**

```bash
git add AgentNotch/App/AppDelegate.swift AgentNotch/UI/NotchContentView.swift
git commit -m "feat: wire event pipeline — socket server → event parser → session manager → UI"
```

---

## Task 14: Screen Observer (Display Changes)

**Files:**
- Create: `AgentNotch/Window/ScreenObserver.swift`
- Modify: `AgentNotch/App/AppDelegate.swift`

- [ ] **Step 1: Create ScreenObserver**

Create `AgentNotch/Window/ScreenObserver.swift`:

```swift
import AppKit

final class ScreenObserver {
    var onScreenChanged: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenDidChange(_ notification: Notification) {
        onScreenChanged?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
```

- [ ] **Step 2: Wire into AppDelegate**

Add to `AppDelegate`:

```swift
    private var screenObserver: ScreenObserver?

    // In applicationDidFinishLaunching, after setupNotchWindow():
    private func setupScreenObserver() {
        screenObserver = ScreenObserver()
        screenObserver?.onScreenChanged = { [weak self] in
            self?.windowController?.close()
            self?.setupNotchWindow()
        }
    }
```

Call `setupScreenObserver()` at the end of `applicationDidFinishLaunching`.

- [ ] **Step 3: Build and verify**

```bash
swift build
```

Expected: Builds. Window repositions when connecting/disconnecting external displays.

- [ ] **Step 4: Commit**

```bash
git add AgentNotch/Window/ScreenObserver.swift AgentNotch/App/AppDelegate.swift
git commit -m "feat: add ScreenObserver to reposition notch on display changes"
```

---

## Task 15: Status Indicator Animations

**Files:**
- Create: `AgentNotch/UI/Compact/StatusIndicator.swift`
- Modify: `AgentNotch/UI/NotchContentView.swift` (compact section)

- [ ] **Step 1: Create StatusIndicator with per-state animations**

Create `AgentNotch/UI/Compact/StatusIndicator.swift`:

```swift
import SwiftUI

struct StatusIndicator: View {
    let status: SessionStatus

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(animation, value: animating)
            .onAppear { animating = true }
            .onChange(of: status) { animating = false; animating = true }
    }

    private var scale: CGFloat {
        switch status {
        case .thinking:
            animating ? 1.3 : 0.8
        case .permissionWaiting:
            animating ? 1.4 : 0.7
        case .error:
            animating ? 1.5 : 0.5
        case .completed:
            animating ? 0.0 : 1.0
        default:
            1.0
        }
    }

    private var opacity: Double {
        switch status {
        case .completed:
            animating ? 0.0 : 1.0
        default:
            1.0
        }
    }

    private var animation: Animation? {
        switch status {
        case .thinking:
            .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        case .toolRunning:
            .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        case .permissionWaiting:
            .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
        case .error:
            .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
        case .completed:
            .easeOut(duration: 2.0)
        default:
            nil
        }
    }
}
```

- [ ] **Step 2: Update compact content in NotchContentView to use StatusIndicator**

In `NotchContentView`, replace the `Circle()` in `compactContent`:

```swift
    private var compactContent: some View {
        HStack(spacing: 8) {
            ForEach(sessionManager.activeSessions) { session in
                HStack(spacing: 4) {
                    StatusIndicator(status: session.status)
                    Text(session.currentTool?.summary ?? session.status.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
            if sessionManager.activeSessions.isEmpty {
                Text("Agent Notch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
    }
```

- [ ] **Step 3: Build and verify**

```bash
swift build
```

Expected: Builds. Status dots animate according to session state.

- [ ] **Step 4: Commit**

```bash
git add AgentNotch/UI/Compact/StatusIndicator.swift AgentNotch/UI/NotchContentView.swift
git commit -m "feat: add animated StatusIndicator with per-state animations"
```

---

## Task 16: Final Integration Test

- [ ] **Step 1: Run all tests**

```bash
swift test 2>&1
```

Expected: All tests pass.

- [ ] **Step 2: Build release**

```bash
swift build -c release 2>&1
```

Expected: Release build succeeds.

- [ ] **Step 3: Manual smoke test**

1. Run the app: `swift run`
2. Verify: notch overlay appears at the notch position
3. Click the notch area → expands to show "No active sessions"
4. Click again → full panel mode
5. Click outside → collapses back
6. Open Claude Code in a terminal → session should appear in notch
7. Watch status changes as Claude works (thinking → tool running → idle)
8. Token counts should update after each Claude response

- [ ] **Step 4: Commit final state**

```bash
git add -A
git commit -m "feat: Agent Notch MVP — Claude Code monitoring via notch overlay"
```
