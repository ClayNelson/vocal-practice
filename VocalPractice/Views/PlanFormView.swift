import SwiftData
import SwiftUI

/// Make a plan offline, or edit the current one. Shows the phase timeline before saving.
/// Changing the goal date or days off re-runs the phase allocation; other edits keep the phases.
struct PlanFormView: View {
    let song: Song
    let existing: SongPlan?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var loaded = false
    @State private var goalType: GoalType = .showcase
    @State private var goalLabel = ""
    @State private var goalDate = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now
    @State private var approx = false
    @State private var originalKey = ""
    @State private var keyOptions = ""
    @State private var rangeLow = ""
    @State private var rangeHigh = ""
    @State private var minutesPerPass = 6
    @State private var sections: [EditableSection] = []
    @State private var blocked: [EditableBlock] = []
    @State private var questions = ""
    @State private var errorMessage: String?

    private var today: PlanDate { .today() }
    private var goal: PlanDate { PlanDate(goalDate, calendar: .current) }

    var body: some View {
        Form {
            Section("Goal") {
                Picker("Type", selection: $goalType) {
                    ForEach(GoalType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Label, e.g. Vocal showcase", text: $goalLabel)
                DatePicker("Date", selection: $goalDate, displayedComponents: .date)
                Toggle("Date is approximate", isOn: $approx)
            }

            Section {
                TextField("Original key, e.g. A", text: $originalKey)
                TextField("Keys to try, e.g. A, Ab, G", text: $keyOptions)
                TextField("Lowest note, e.g. E3", text: $rangeLow)
                TextField("Highest note, e.g. F#4", text: $rangeHigh)
            } header: {
                Text("Song")
            } footer: {
                Text("Notes in the original key. The first key to try is the current pick.")
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()

            Section("Practice") {
                Stepper("\(minutesPerPass) min per pass", value: $minutesPerPass, in: 2...20)
            }

            Section {
                ForEach($sections) { $section in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Section, e.g. Top phrases", text: $section.title)
                            Picker("Difficulty", selection: $section.difficulty) {
                                ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            .labelsHidden()
                        }
                        TextField("What to work on", text: $section.focus, axis: .vertical)
                            .font(.footnote)
                    }
                }
                .onDelete { sections.remove(atOffsets: $0) }
                .onMove { sections.move(fromOffsets: $0, toOffset: $1) }
                Button("Add section") { sections.append(EditableSection()) }
            } header: {
                HStack { Text("Sections"); Spacer(); EditButton().font(.caption) }
            } footer: {
                Text(sections.isEmpty ? "None yet: the plan uses Hardest phrase and Ending. Name spots by what they are, not their words."
                                      : "Name spots by what they are, not their words.")
            }

            Section {
                ForEach($blocked) { $block in
                    VStack {
                        TextField("Label, e.g. Holiday maintenance", text: $block.label)
                        DatePicker("From", selection: $block.start, displayedComponents: .date)
                        DatePicker("To", selection: $block.end, in: block.start..., displayedComponents: .date)
                    }
                }
                .onDelete { blocked.remove(atOffsets: $0) }
                Button("Add days off") {
                    blocked.append(EditableBlock(start: .now, end: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now))
                }
            } header: {
                Text("Days off")
            } footer: {
                Text("Holidays or travel become maintenance: two or three full runs a week, nothing new.")
            }

            Section("Questions for your teacher") {
                TextField("One per line", text: $questions, axis: .vertical).lineLimit(2...8)
            }

            if problems.isEmpty {
                let preview = build()
                Section("Preview") {
                    PhaseTimeline(phases: preview.phases)
                    ForEach(preview.checkpoints, id: \.title) { checkpoint in
                        LabeledContent(checkpoint.title,
                                       value: checkpoint.due.date(in: .current).formatted(.dateTime.month(.abbreviated).day()))
                            .font(.footnote)
                    }
                    if let key = preview.assessment?.keyRecommendation { Text(key).font(.footnote) }
                }
            } else {
                Section("Before you save") {
                    ForEach(problems, id: \.self) { Label($0, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                }
            }
        }
        .navigationTitle(existing == nil ? "Make a plan" : "Edit plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!problems.isEmpty) }
        }
        .alert("Couldn't save the plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear(perform: load)
    }

    // MARK: Form state

    private var problems: [String] {
        var result: [String] = []
        if song.title.isEmpty { result.append("Give the song a title.") }
        if song.artist.isEmpty { result.append("Add the artist on the song screen.") }
        if NoteName.key(originalKey) == nil { result.append("Enter the original key, like A or Bb.") }
        for key in keyList where NoteName.key(key) == nil { result.append("'\(key)' isn't a key.") }
        for note in [rangeLow, rangeHigh] where !note.isEmpty && NoteName.midi(note) == nil {
            result.append("'\(note)' isn't a note like E3 or F#4.")
        }
        if existing == nil && goal < today { result.append("Pick a goal date from today on.") }
        return result
    }

    private var keyList: [String] {
        keyOptions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var planSections: [PlanSection] {
        var used = Set<String>()
        return sections.enumerated().compactMap { index, section in
            let title = section.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            var id = section.sectionID ?? PlanFormat.kebab(title)
            if id.isEmpty { id = "section-\(index + 1)" }
            let base = id
            var n = 2
            while used.contains(id) { id = "\(base)-\(n)"; n += 1 }
            used.insert(id)
            return PlanSection(id: id, title: title, difficulty: section.difficulty, focus: section.focus)
        }
    }

    private var planBlocks: [PlanBlockedRange] {
        blocked.map { block in
            let label = block.label.trimmingCharacters(in: .whitespaces)
            return PlanBlockedRange(start: PlanDate(block.start, calendar: .current), end: PlanDate(block.end, calendar: .current),
                                    label: label.isEmpty ? "Days off" : label)
        }
    }

    private func build() -> SongPlan {
        let questionList = questions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var request = PlanRequest(title: song.title, artist: song.artist, goalType: goalType, goalLabel: goalLabel,
                                  goalDate: goal, goalDateIsApprox: approx, start: today, originalKey: originalKey,
                                  keyOptions: keyList, rangeLow: rangeLow, rangeHigh: rangeHigh,
                                  minutesPerPass: minutesPerPass, sections: planSections, blocked: planBlocks,
                                  questionsForTeacher: questionList, assessment: existing?.assessment)
        guard let existing else { return OfflinePlanner.makePlan(request) }

        var plan: SongPlan
        if existing.goal.date != goal || (existing.blockedRanges ?? []) != planBlocks {
            request.start = existing.phases.first?.start ?? today
            plan = OfflinePlanner.makePlan(request)
        } else {
            plan = existing
            let ids = request.sections.isEmpty ? OfflinePlanner.defaultSections.map(\.id) : request.sections.map(\.id)
            for i in plan.phases.indices {
                plan.phases[i].focusSections.removeAll { !ids.contains($0) }
                if plan.phases[i].songBlock == .sections && plan.phases[i].focusSections.isEmpty {
                    plan.phases[i].focusSections = ids
                }
            }
            plan.sections = request.sections.isEmpty ? OfflinePlanner.defaultSections : request.sections
        }
        // Fields the form edits apply either way; provenance and references stay from the original.
        plan.goal = PlanGoal(type: goalType, label: goalLabel, date: goal, dateIsApprox: approx)
        plan.song.title = song.title
        plan.song.artist = song.artist
        plan.song.reference = existing.song.reference
        plan.song.tempoBPM = existing.song.tempoBPM
        plan.song.originalKey = originalKey
        plan.song.keyOptions = keyList
        plan.song.range = request.rangeLow?.isEmpty == false || request.rangeHigh?.isEmpty == false
            ? PlanRange(low: rangeLow.isEmpty ? nil : rangeLow, high: rangeHigh.isEmpty ? nil : rangeHigh) : nil
        plan.song.minutesPerPass = minutesPerPass
        plan.questionsForTeacher = questionList
        plan.myOpsPath = existing.myOpsPath
        plan.generatedBy = existing.generatedBy
        plan.generatedAt = existing.generatedAt
        plan.assessment = existing.assessment
        return plan
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let plan = existing else {
            originalKey = song.key
            keyOptions = song.key
            minutesPerPass = max(2, min(20, song.minutes))
            goalType = song.showcase ? .showcase : .none
            return
        }
        goalType = plan.goal.type
        goalLabel = plan.goal.label
        goalDate = plan.goal.date.date(in: .current)
        approx = plan.goal.dateIsApprox
        originalKey = plan.song.originalKey
        keyOptions = plan.song.keyOptions.joined(separator: ", ")
        rangeLow = plan.song.range?.low ?? ""
        rangeHigh = plan.song.range?.high ?? ""
        minutesPerPass = plan.song.minutesPerPass
        sections = plan.sections.map {
            EditableSection(sectionID: $0.id, title: $0.title, difficulty: $0.difficulty, focus: $0.focus)
        }
        blocked = (plan.blockedRanges ?? []).map {
            EditableBlock(start: $0.start.date(in: .current), end: $0.end.date(in: .current), label: $0.label)
        }
        questions = plan.questionsForTeacher.joined(separator: "\n")
    }

    private func save() {
        do {
            try PlanStore.apply(build(), to: song, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditableSection: Identifiable {
    let id = UUID()
    /// Kept for sections from an existing plan so their ratings carry over.
    var sectionID: String?
    var title = ""
    var difficulty: Difficulty = .medium
    var focus = ""
}

struct EditableBlock: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var label = ""
}
