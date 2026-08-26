import Darwin
import Foundation

/// Reads the directory a running process is currently in.
///
/// The `PWD` variable a shell exports is the environment a process was *started* with, which is a
/// different fact: a session VS Code starts from an extension inherits `PWD=/` from the extension
/// host no matter which project it opens. The kernel's own record of the working directory answers
/// for the process as it is now. Only processes owned by the same user are readable, which is all
/// this app needs.
enum ProcessWorkingDirectory {
    static func path(ofPID pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }

        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }
}
