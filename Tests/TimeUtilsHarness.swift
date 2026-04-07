import Foundation

func testTimeUtils() throws {
  try testBusinessDays()
  try testRelativeTimeFormatting()
}

private func testBusinessDays() throws {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!

  let weekdayDate = DateComponents(
    calendar: calendar,
    year: 2026,
    month: 4,
    day: 7
  ).date!

  try expect(
    TimeUtils.businessDaysThisMonth(now: weekdayDate, calendar: calendar) == 5,
    "business day count should include weekdays through current day"
  )

  let sundayDate = DateComponents(
    calendar: calendar,
    year: 2026,
    month: 4,
    day: 5
  ).date!

  try expect(
    TimeUtils.businessDaysThisMonth(now: sundayDate, calendar: calendar) == 3,
    "weekends should not increase the business day count"
  )

  let firstDayOfMonth = DateComponents(
    calendar: calendar,
    year: 2026,
    month: 11,
    day: 1
  ).date!

  try expect(
    TimeUtils.businessDaysThisMonth(now: firstDayOfMonth, calendar: calendar) == 0,
    "a weekend on the first day of the month should count as zero business days"
  )
}

private func testRelativeTimeFormatting() throws {
  let now = Date(timeIntervalSinceReferenceDate: 1_000)

  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(60), now: now) == "just now",
    "future dates should clamp to just now"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-4), now: now) == "just now",
    "times under five seconds should be just now"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-5), now: now) == "5s ago",
    "five-second boundary should switch to seconds"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-59), now: now) == "59s ago",
    "sub-minute values should stay in seconds"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-60), now: now) == "1m ago",
    "sixty-second boundary should switch to minutes"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-(59 * 60 + 59)), now: now)
      == "59m ago",
    "sub-hour values should stay in minutes"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-3600), now: now) == "1h ago",
    "one-hour boundary should switch to hours"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-(23 * 3600 + 3599)), now: now)
      == "23h ago",
    "sub-day values should stay in hours"
  )
  try expect(
    TimeUtils.formatRelativeTime(since: now.addingTimeInterval(-86400), now: now) == "1d ago",
    "one-day boundary should switch to days"
  )
}
