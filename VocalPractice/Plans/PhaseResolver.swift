import Foundation

enum PhaseResolver {
    /// The phase containing `day`, or nil before the first phase and after the goal.
    static func current(plan: SongPlan, on day: PlanDate) -> PlanPhase? {
        plan.phases.first { $0.start <= day && day <= $0.end }
    }

    static func current(plan: SongPlan, on date: Date, calendar: Calendar) -> PlanPhase? {
        current(plan: plan, on: PlanDate(date, calendar: calendar))
    }
}

enum PlanFormat {
    /// "13 weeks, 3 days", "about 2 weeks", "Today". Counts from `today` to `goal`.
    static func countdown(from today: PlanDate, to goal: PlanDate, approx: Bool) -> String {
        let days = today.daysUntil(goal)
        if days < 0 { return "Past" }
        if days == 0 { return "Today" }
        let weeks = days / 7, rest = days % 7
        var parts: [String] = []
        if weeks > 0 { parts.append(weeks == 1 ? "1 week" : "\(weeks) weeks") }
        if rest > 0 { parts.append(rest == 1 ? "1 day" : "\(rest) days") }
        return (approx ? "about " : "") + parts.joined(separator: ", ")
    }

    /// "Top phrases" to "top-phrases"; used for section ids and export file names.
    static func kebab(_ text: String) -> String {
        let kept = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(kept).split(separator: " ").joined(separator: "-")
    }

    /// "A, Ab, or G"
    static func list(_ items: [String], conjunction: String = "or") -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) \(conjunction) \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", \(conjunction) \(items.last!)"
        }
    }
}
