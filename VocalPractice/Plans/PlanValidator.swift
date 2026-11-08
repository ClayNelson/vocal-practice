import Foundation

/// Swift port of tools/validate_plan.py. Same rules, so a plan that passes one passes the other.
enum PlanValidator {
    static func validate(_ plan: SongPlan) -> [String] {
        var errors: [String] = []
        if plan.schemaVersion != 1 { errors.append("schemaVersion must be 1") }

        let song = plan.song
        if song.title.isEmpty { errors.append("song.title is required") }
        if song.artist.isEmpty { errors.append("song.artist is required") }
        if song.originalKey.isEmpty { errors.append("song.originalKey is required") }
        if song.minutesPerPass <= 0 { errors.append("song.minutesPerPass is required") }
        for (field, note) in [("low", song.range?.low), ("high", song.range?.high)] {
            if let note, !note.isEmpty, NoteName.midi(note) == nil {
                errors.append("song.range.\(field) '\(note)' is not a note like E3 or F#4")
            }
        }

        let sectionIDs = Set(plan.sections.map(\.id))
        if plan.phases.isEmpty { errors.append("at least one phase is required") }
        var previousEnd: PlanDate?
        for phase in plan.phases {
            if phase.end < phase.start { errors.append("phase \(phase.id): ends before it starts") }
            if let previousEnd, phase.start != previousEnd.adding(days: 1) {
                errors.append("phase \(phase.id): starts \(phase.start), expected \(previousEnd.adding(days: 1)) (gap or overlap)")
            }
            for id in phase.focusSections where !sectionIDs.contains(id) {
                errors.append("phase \(phase.id): unknown section '\(id)'")
            }
            previousEnd = phase.end
        }
        if let last = plan.phases.last {
            if last.songBlock != .taper { errors.append("last phase must be a taper") }
            if last.end != plan.goal.date { errors.append("last phase must end on goal.date") }
        }

        for block in plan.blockedRanges ?? [] where block.end < block.start {
            errors.append("blocked range '\(block.label)': ends before it starts")
        }
        return errors
    }

    /// Decodes then validates. Returns a plan only when there are no errors, so nothing half-applies.
    static func check(_ data: Data) -> (plan: SongPlan?, errors: [String]) {
        let plan: SongPlan
        do {
            plan = try SongPlan.decode(data)
        } catch {
            return (nil, [describe(error)])
        }
        let errors = validate(plan)
        return (errors.isEmpty ? plan : nil, errors)
    }

    /// Plain wording for decoding failures, naming the field ("goal.type", "phases.2.start").
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        func path(_ keys: [CodingKey]) -> String {
            keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty { return "The file isn't valid plan JSON." }
            return "\(path(context.codingPath)) \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])) is required"
        case .valueNotFound(_, let context):
            return "\(path(context.codingPath)) is required"
        case .typeMismatch(_, let context):
            return "\(path(context.codingPath)) has the wrong type"
        @unknown default:
            return error.localizedDescription
        }
    }
}
