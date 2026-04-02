import Foundation

public enum TokenFormatter {
    public static func format(_ count: Int) -> String {
        if count == 0 {
            return "0"
        } else if count < 1_000 {
            return "\(count)"
        } else if count < 1_000_000 {
            let value = Double(count) / 1_000.0
            return String(format: "%.1fk", value)
        } else {
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        }
    }
}
