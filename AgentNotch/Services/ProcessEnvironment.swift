import Foundation

/// Reads the environment a running process was started with.
///
/// `ps eww` prints the same block, but only after the argument vector, on one whitespace-separated
/// line — a prompt that happens to contain `KEY=value` is indistinguishable from a real variable
/// there. `KERN_PROCARGS2` hands over the regions separately, so the environment can be read for
/// what it is. Only processes owned by the same user are readable, which is all this app needs.
enum ProcessEnvironment {
    static func environment(ofPID pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return parse(processArguments: Data(buffer.prefix(size)))
    }

    /// Splits a `KERN_PROCARGS2` block into its environment entries.
    ///
    /// Layout: `argc` as a 32-bit count, the executable path, alignment padding, `argc`
    /// NUL-terminated arguments, then the environment as NUL-terminated `KEY=value` entries. The
    /// argument count is what makes the boundary knowable: without it there is nothing to
    /// distinguish the last argument from the first variable.
    static func parse(processArguments data: Data) -> [String: String]? {
        let countWidth = 4
        guard data.count > countWidth else { return nil }

        let argumentCount = data[data.startIndex..<data.startIndex + countWidth]
            .withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argumentCount >= 0 else { return nil }

        var index = data.startIndex + countWidth

        // The executable path, followed by the NUL padding that aligns the argument vector.
        guard let pathEnd = data[index...].firstIndex(of: 0) else { return nil }
        index = pathEnd + 1
        while index < data.endIndex, data[index] == 0 {
            index += 1
        }

        var remainingArguments = Int(argumentCount)
        while remainingArguments > 0, index < data.endIndex {
            guard let end = data[index...].firstIndex(of: 0) else { return nil }
            index = end + 1
            remainingArguments -= 1
        }

        var environment: [String: String] = [:]
        while index < data.endIndex {
            guard let end = data[index...].firstIndex(of: 0) else { break }
            // An empty entry closes the block; anything after it is not environment data.
            if end == index { break }
            if let entry = String(data: data[index..<end], encoding: .utf8),
                let separator = entry.firstIndex(of: "=")
            {
                environment[String(entry[..<separator])] =
                    String(entry[entry.index(after: separator)...])
            }
            index = end + 1
        }
        return environment
    }
}
