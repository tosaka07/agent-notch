import Foundation

public enum RelativeTimeFormatter {
    public static func format(since referenceDate: Date, relativeTo now: Date = Date()) -> String {
        let clampedNow = max(now, referenceDate)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: referenceDate, to: clampedNow)

        if let year = components.year, year >= 1 {
            return "\(year)年前"
        }
        if let month = components.month, month >= 1 {
            return "\(month)ヵ月前"
        }
        if let day = components.day, day >= 1 {
            return "\(day)日前"
        }
        if let hour = components.hour, hour >= 1 {
            return "\(hour)時間前"
        }
        if let minute = components.minute, minute >= 1 {
            return "\(minute)分前"
        }

        return "\(max(components.second ?? 0, 0))秒前"
    }
}
