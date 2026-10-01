import SwiftUI

/// While a day is still unfolding, "5 minutes ago" says more than a clock time.
/// Once the day is over that reading collapses — every row would say "2 days
/// ago" — so past days keep the clock.
enum TimeLabel {
    static func text(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        guard calendar.isDateInToday(date) else {
            return date.formatted(.dateTime.hour().minute())
        }
        guard now.timeIntervalSince(date) >= 60 else {
            return "just now"
        }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    }
}

/// A single timestamp that keeps itself current as the minutes pass.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        if Calendar.current.isDateInToday(date) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(TimeLabel.text(for: date, now: context.date))
            }
        } else {
            Text(TimeLabel.text(for: date, now: .now))
        }
    }
}
