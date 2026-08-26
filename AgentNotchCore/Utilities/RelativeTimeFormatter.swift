import Foundation

public enum RelativeTimeFormatter {
    public static func format(since referenceDate: Date, relativeTo now: Date = Date()) -> String {
        let clampedNow = max(now, referenceDate)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: referenceDate, to: clampedNow)

        if let year = components.year, year >= 1 {
            return AppLocalization.localized("\(year)y ago")
        }
        if let month = components.month, month >= 1 {
            return AppLocalization.localized("\(month)mo ago")
        }
        if let day = components.day, day >= 1 {
            return AppLocalization.localized("\(day)d ago")
        }
        if let hour = components.hour, hour >= 1 {
            return AppLocalization.localized("\(hour)h ago")
        }
        if let minute = components.minute, minute >= 1 {
            return AppLocalization.localized("\(minute)m ago")
        }

        let second = max(components.second ?? 0, 0)
        return AppLocalization.localized("\(second)s ago")
    }
}
