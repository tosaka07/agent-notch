import Darwin
import Foundation

/// Reads the directory a running process is currently in.
///
/// The `PWD` variable a shell exports is the environment a process was *started* with, which is a
/// different fact: a session VS Code starts from an extension inherits `PWD=/` from the extension
/// host no matter which project it opens. The kernel's own record of the working directory answers
/// for the process as it is now. Only processes owned by the same user are readable, which is all
/// this app needs.
///
/// `proc_pidinfo` is libproc's own interface rather than a documented framework API, so the one
/// call is kept here alone. Every caller treats nil as "the directory is unknown" and carries on
/// without it, which is also what a future macOS that stops answering would produce.
enum ProcessWorkingDirectory {
    static func path(ofPID pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }

        // The kernel writes a NUL-terminated path into a fixed-length field. Decoding stops at
        // that terminator, and a field without one is not a path this can read.
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { field -> String? in
            guard let end = field.firstIndex(of: 0) else { return nil }
            return String(decoding: field[..<end], as: UTF8.self)
        }
        return (path?.isEmpty ?? true) ? nil : path
    }
}
