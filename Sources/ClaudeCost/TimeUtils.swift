import Foundation

public enum TimeUtils {
  public static func businessDaysThisMonth(now: Date = Date(), calendar: Calendar = .current) -> Int
  {
    guard let interval = calendar.dateInterval(of: .month, for: now) else {
      return 0
    }

    let startOfMonth = interval.start
    let todayDay = calendar.component(.day, from: now)

    return (0..<todayDay).reduce(0) { count, offset in
      guard let date = calendar.date(byAdding: .day, value: offset, to: startOfMonth) else {
        return count
      }

      let weekday = calendar.component(.weekday, from: date)
      return (2...6).contains(weekday) ? count + 1 : count
    }
  }

  public static func formatRelativeTime(since date: Date, now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))

    if seconds < 5 {
      return "just now"
    }
    if seconds < 60 {
      return "\(seconds)s ago"
    }

    let minutes = seconds / 60
    if minutes < 60 {
      return "\(minutes)m ago"
    }

    let hours = minutes / 60
    if hours < 24 {
      return "\(hours)h ago"
    }

    let days = hours / 24
    return "\(days)d ago"
  }
}
