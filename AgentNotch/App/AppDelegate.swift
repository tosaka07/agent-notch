import AgentNotchCore
import AppKit

/// アプリのエントリーポイント（コンポジションルート）。
/// 各 Coordinator を組み立てて起動順に start を呼ぶだけの薄い層。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sessionManager = SessionManager()

    private lazy var statusBar = StatusBarCoordinator(sessionManager: sessionManager)
    private lazy var socket = SocketCoordinator(sessionManager: sessionManager)
    private lazy var display = DisplayCoordinator(
        sessionManager: sessionManager,
        permissionActions: socket.permissionActions
    )
    private lazy var sweep = SessionSweepCoordinator(sessionManager: sessionManager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.bootstrap()
        statusBar.install()
        socket.start()
        display.start()
        sweep.start()
        HotKeyCoordinator.register()
        HookInstaller.installIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sweep.stop()
        display.stop()
        socket.stop()
    }
}
