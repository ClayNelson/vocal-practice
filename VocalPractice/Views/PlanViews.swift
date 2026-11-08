import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: Today

/// The nearest active goal: countdown, current phase, and the next open checkpoint.
struct GoalCard: View {
    let song: Song
    let plan: SongPlan
    let today: PlanDate

    private var nextCheckpoint: Checkpoint? {
        song.checkpoints.filter { !$0.done }.min { $0.due < $1.due }
    }

    var body: some View {
        NavigationLink { SongDetailView(song: song) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(plan.goal.displayLabel) · \(PlanFormat.countdown(from: today, to: plan.goal.date, approx: plan.goal.dateIsApprox))")
                    .font(.headline)
                if let phase = PhaseResolver.current(plan: plan, on: today) {
                    Text(phase.title).foregroundStyle(.indigo)
                }
                if let next = nextCheckpoint {
                    let overdue = PlanDate(next.due, calendar: .current) < today
                    Text("\(next.title), \(overdue ? "was due" : "due") \(next.due.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.footnote).foregroundStyle(overdue ? .orange : .secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

extension PlanGoal {
    var displayLabel: String {
        if !label.isEmpty { return label }
        return type == .none ? "Goal" : type.label
    }
}

// MARK: Song detail

/// The Plan part of a song's detail screen: make or import one, or show and manage the current plan.
struct SongPlanSections: View {
    let song: Song
    /// Every take of this song, for per-section counts.
    let takes: [Take]
    @Binding var sectionFilter: String?

    @Environment(\.modelContext) private var context
    @State private var form: PlanFormMode?
    @State private var importing = false
    @State private var pendingImport: SongPlan?
    @State private var confirmRemove = false
    @State private var errorMessage: String?

    private var today: PlanDate { .today() }

    var body: some View {
        if let plan = PlanStore.currentPlan(for: song) {
            planSections(plan)
        } else {
            Section {
                formButton(.make)
                importButton
            } header: {
                Text("Plan")
            } footer: {
                Text("A plan works toward a dated goal, like a showcase. Each day's session follows its current phase.")
            }
        }
    }

    // Each presentation hangs off its own button. Inside a Form, modifiers on a Group or Section
    // repeat on every row, and a sheet and a file importer on one view interfere with each other.

    private func formButton(_ mode: PlanFormMode) -> some View {
        Button { form = mode } label: {
            mode == .make ? Label("Make a plan", systemImage: "calendar.badge.plus") : Label("Edit plan", systemImage: "pencil")
        }
        .sheet(item: $form) { mode in
            NavigationStack { PlanFormView(song: song, existing: mode == .edit ? PlanStore.currentPlan(for: song) : nil) }
        }
    }

    private var importButton: some View {
        Button { importing = true } label: { Label("Import plan", systemImage: "square.and.arrow.down") }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let (plan, errors) = PlanValidator.check((try? PlanStore.read(url)) ?? Data())
                guard let plan else { errorMessage = errors.joined(separator: "\n"); return }
                if song.planJSON == nil { apply(plan) } else { pendingImport = plan }
            }
            .confirmationDialog("Replace this plan?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                                titleVisibility: .visible) {
                Button("Replace plan") { if let plan = pendingImport { apply(plan) } }
            } message: {
                Text("Section ratings carry over for sections with the same id.")
            }
            .alert("Couldn't use that plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private var removeButton: some View {
        Button(role: .destructive) { confirmRemove = true } label: { Label("Remove plan", systemImage: "trash") }
            .confirmationDialog("Remove this plan?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove plan", role: .destructive) {
                    sectionFilter = nil
                    PlanStore.removePlan(from: song, in: context)
                }
            } message: {
                Text("The song and its takes stay. Phases, sections, and checkpoints are removed.")
            }
    }

    private func apply(_ plan: SongPlan) {
        do { try PlanStore.apply(plan, to: song, in: context) } catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func planSections(_ plan: SongPlan) -> some View {
        let current = PhaseResolver.current(plan: plan, on: today)

        Section("Goal") {
            LabeledContent(plan.goal.displayLabel,
                           value: PlanFormat.countdown(from: today, to: plan.goal.date, approx: plan.goal.dateIsApprox))
            LabeledContent("Date", value: plan.goal.date.date(in: .current).formatted(date: .abbreviated, time: .omitted)
                           + (plan.goal.dateIsApprox ? " (approximate)" : ""))
            if !plan.song.keyOptions.isEmpty {
                LabeledContent("Keys", value: plan.song.keyOptions.joined(separator: ", "))
            }
            if let range = plan.song.range, let low = range.low, let high = range.high {
                LabeledContent("Range", value: "\(low) to \(high)")
            }
            if let reference = plan.song.reference { LabeledContent("Reference", value: reference) }
        }

        Section("Phases") {
            PhaseTimeline(phases: plan.phases, current: current?.id)
        }

        Section {
            ForEach(song.sections.sorted { $0.order < $1.order }) { section in
                Button {
                    sectionFilter = sectionFilter == section.sectionID ? nil : section.sectionID
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            // Explicit colors: inside a Button, .primary would pick up the tint.
                            Text(section.title).foregroundStyle(Color.primary)
                            if !section.focus.isEmpty {
                                Text(section.focus).font(.caption).foregroundStyle(Color.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if let rating = section.lastRating.flatMap(SectionRating.init) { RatingBadge(rating: rating) }
                            Text("\(takes.filter { $0.sectionID == section.sectionID }.count) takes")
                                .font(.caption).foregroundStyle(Color.secondary)
                        }
                        if sectionFilter == section.sectionID {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill").foregroundStyle(.indigo)
                        }
                    }
                }
            }
        } header: {
            Text("Sections")
        } footer: {
            Text(sectionFilter == nil ? "Tap a section to show only its takes." : "Showing takes for one section. Tap it again to show all.")
        }

        if !song.checkpoints.isEmpty {
            Section("Checkpoints") {
                ForEach(song.checkpoints.sorted { $0.due < $1.due }) { checkpoint in
                    let overdue = !checkpoint.done && PlanDate(checkpoint.due, calendar: .current) < today
                    Toggle(isOn: Binding(get: { checkpoint.done }, set: { checkpoint.done = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkpoint.title)
                            Text(checkpoint.due.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(overdue ? .orange : .secondary)
                        }
                    }
                }
            }
        }

        if let assessment = plan.assessment {
            Section("Assessment") {
                if let summary = assessment.summary { Text(summary) }
                if let key = assessment.keyRecommendation { Label(key, systemImage: "music.quarternote.3") }
                ForEach(assessment.sources ?? [], id: \.url) { source in
                    if let url = URL(string: source.url) { Link(source.title, destination: url) }
                }
            }
        }

        if !plan.questionsForTeacher.isEmpty {
            Section("Questions for your teacher") {
                ForEach(plan.questionsForTeacher, id: \.self) { Text($0) }
            }
        }

        Section {
            if let export = PlanStore.export(for: song) {
                ShareLink(item: export, preview: SharePreview(export.fileName)) {
                    Label("Export plan", systemImage: "square.and.arrow.up")
                }
            }
            formButton(.edit)
            importButton
            removeButton
        }
    }
}

enum PlanFormMode: String, Identifiable {
    case make, edit
    var id: String { rawValue }
}

/// Phases in order with dates; the current one is highlighted.
struct PhaseTimeline: View {
    let phases: [PlanPhase]
    var current: String?

    var body: some View {
        ForEach(phases) { phase in
            let isCurrent = phase.id == current
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isCurrent ? "circle.inset.filled" : "circle")
                    .foregroundStyle(isCurrent ? .indigo : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title).fontWeight(isCurrent ? .semibold : .regular)
                    Text("\(Self.span(phase)) · \(phase.songBlock.label)")
                        .font(.caption).foregroundStyle(.secondary)
                    if isCurrent, let notes = phase.notes, !notes.isEmpty {
                        Text(notes).font(.caption)
                    }
                }
            }
            .listRowBackground(isCurrent ? Color.indigo.opacity(0.08) : nil)
        }
    }

    static func span(_ phase: PlanPhase) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let start = phase.start.date(in: .current).formatted(style), end = phase.end.date(in: .current).formatted(style)
        let days = phase.days == 1 ? "1 day" : "\(phase.days) days"
        return phase.days == 1 ? "\(start), \(days)" : "\(start) to \(end), \(days)"
    }
}

extension SongBlock {
    var label: String {
        switch self {
        case .listen: "Listen"
        case .sections: "Sections"
        case .fullRun: "Full runs"
        case .maintenance: "Maintenance"
        case .taper: "Taper"
        }
    }
}

struct RatingBadge: View {
    let rating: SectionRating
    var body: some View {
        Text(rating.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch rating { case .free: .green; case .pressed: .orange; case .cracked: .red }
    }
}
