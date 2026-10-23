import SwiftData
import SwiftUI

/// Runs a planned session item by item: play Nicolette's track, record a take, mark solid, next.
struct SessionPlayerView: View {
    let plan: SessionPlan
    let voiceCondition: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var warmups: [Warmup]
    @Query private var songs: [Song]

    @State private var index = 0
    @State private var completed: Set<UUID> = []
    @State private var markedSolid: Set<UUID> = []
    @State private var takes: [PendingTake] = []
    /// Ratings given this session, by section id.
    @State private var sectionRatings: [String: SectionRating] = [:]
    @State private var askRating = false
    @State private var notes = ""
    @State private var finished = false
    @State private var player = TrackPlayer()
    @State private var recorder = TakeRecorder()
    @State private var micDenied = false

    private var item: PlanItem? { plan.items.indices.contains(index) ? plan.items[index] : nil }

    var body: some View {
        NavigationStack {
            Group {
                if finished || item == nil { summary } else if let item { itemView(item) }
            }
            .navigationTitle(finished ? "Nice work" : "\(index + 1) of \(plan.items.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { player.stop(); _ = recorder.stop(); dismiss() }
                }
            }
        }
        .onChange(of: index, initial: true) { loadTrack() }
    }

    // MARK: Item

    @ViewBuilder
    private func itemView(_ item: PlanItem) -> some View {
        VStack(spacing: 24) {
            ProgressView(value: Double(index), total: Double(plan.items.count)).padding(.horizontal)
            Text(sectionLabel(item)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(item.title).font(.largeTitle.bold()).multilineTextAlignment(.center).padding(.horizontal)
            details(for: item)
            Spacer()

            if hasTrack(item) {
                VStack {
                    ProgressView(value: player.progress).padding(.horizontal, 40)
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 72))
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause track" : "Play track")
                }
            } else if case .warmup(let w) = item {
                if let link = warmupModel(w.id)?.linkURL.flatMap(URL.init) {
                    Link(destination: link) { Label("Watch on YouTube", systemImage: "play.rectangle") }
                        .buttonStyle(.bordered)
                } else {
                    Text("No track yet. Import Nicolette's m4a on the Warmups tab.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Button { toggleRecording(item) } label: {
                Label(recorder.isRecording ? "Stop take" : "Record take",
                      systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
            }
            .buttonStyle(.bordered).tint(recorder.isRecording ? .red : .primary)
            if micDenied {
                Text("Microphone access is off. Turn it on in Settings to record takes.")
                    .font(.footnote).foregroundStyle(.red)
            }
            if askRating, sectionID(item) != nil {
                VStack(spacing: 8) {
                    Text("How did it feel?").font(.headline)
                    HStack {
                        ForEach(SectionRating.allCases, id: \.self) { rating in
                            Button(rating.label) { rate(item, rating) }.buttonStyle(.bordered)
                        }
                    }
                }
            }

            if case .warmup(let w) = item {
                Toggle("Solid: move up the ladder next time", isOn: Binding(
                    get: { markedSolid.contains(w.id) },
                    set: { if $0 { markedSolid.insert(w.id) } else { markedSolid.remove(w.id) } }))
                .padding(.horizontal, 32)
            }

            HStack {
                Button("Skip") { advance(completedCurrent: false) }.buttonStyle(.bordered)
                Button("Done, next") { advance(completedCurrent: true) }.buttonStyle(.borderedProminent)
            }
            .padding(.bottom)
        }
    }

    @ViewBuilder
    private func details(for item: PlanItem) -> some View {
        if case .song(let s, let mode) = item, let song = songs.first(where: { $0.id == s.id }) {
            VStack(spacing: 8) {
                if let label = mode.label { Text(label).font(.headline).foregroundStyle(.indigo) }
                if case .section(_, let title, let focus) = mode {
                    Text(title).font(.title3.bold())
                    if !focus.isEmpty { Text(focus).multilineTextAlignment(.center).padding(.horizontal) }
                }
                if case .listen = mode, let plan = PlanStore.currentPlan(for: song) {
                    if let reference = plan.song.reference { Text("Reference: \(reference)") }
                    if let notes = PhaseResolver.current(plan: plan, on: .now, calendar: .current)?.notes {
                        Text(notes).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    Text("Recording is optional while listening.").font(.footnote).foregroundStyle(.secondary)
                }
                if !song.key.isEmpty { Text("Key: \(song.key)").font(.headline) }
                if !song.notes.isEmpty { Text(song.notes).foregroundStyle(.secondary) }
                if !song.lyrics.isEmpty {
                    ScrollView { Text(song.lyrics).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 220).padding(.horizontal)
                }
            }
        } else {
            Text("\(item.minutes) min").foregroundStyle(.secondary)
        }
    }

    // MARK: Summary

    private var summary: some View {
        Form {
            Section {
                LabeledContent("Completed", value: "\(completed.count) of \(plan.items.count)")
                LabeledContent("Takes recorded", value: "\(takes.count)")
                if !markedSolid.isEmpty { LabeledContent("Moved up", value: "\(markedSolid.count) warmup(s)") }
            }
            Section("Notes for next lesson") {
                TextField("What felt good, what's stuck", text: $notes, axis: .vertical).lineLimit(3...6)
            }
            Section {
                Button("Save session") { save(); dismiss() }.frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Actions

    private func sectionLabel(_ item: PlanItem) -> String {
        if case .warmup = item { return "WARMUP" } else { return "SONG" }
    }

    private func warmupModel(_ id: UUID) -> Warmup? { warmups.first { $0.id == id } }

    private func sectionID(_ item: PlanItem) -> String? {
        if case .song(_, .section(let id, _, _)) = item { return id }
        return nil
    }

    private func keepTake(_ item: PlanItem, _ file: String) {
        takes.append(PendingTake(itemID: item.id, title: item.title, file: file, sectionID: sectionID(item)))
        askRating = sectionID(item) != nil
    }

    /// Rates the latest take of a section and remembers it for the section.
    private func rate(_ item: PlanItem, _ rating: SectionRating) {
        guard let id = sectionID(item) else { return }
        if let last = takes.lastIndex(where: { $0.itemID == item.id }) { takes[last].rating = rating.rawValue }
        sectionRatings[id] = rating
        askRating = false
    }

    private func hasTrack(_ item: PlanItem) -> Bool {
        if case .warmup(let w) = item { return warmupModel(w.id)?.audioFileName != nil }
        return false
    }

    private func loadTrack() {
        player.stop()
        guard let item, case .warmup(let w) = item, let name = warmupModel(w.id)?.audioFileName else { return }
        player.load(AudioStorage.warmups.appending(path: name))
    }

    private func toggleRecording(_ item: PlanItem) {
        if recorder.isRecording {
            if let name = recorder.stop() { keepTake(item, name) }
            return
        }
        Task {
            guard await recorder.requestPermission() else { micDenied = true; return }
            try? recorder.start()
        }
    }

    private func advance(completedCurrent: Bool) {
        if recorder.isRecording, let item, let name = recorder.stop() { takes.append(
            PendingTake(itemID: item.id, title: item.title, file: name, sectionID: sectionID(item))) }
        askRating = false
        if completedCurrent, let item { completed.insert(item.id) }
        if index + 1 < plan.items.count { index += 1 } else { player.stop(); finished = true }
    }

    private func save() {
        let session = PracticeSession(plannedMinutes: plan.targetMinutes, voiceCondition: voiceCondition)
        session.completedItemIDs = Array(completed)
        session.notes = notes
        context.insert(session)
        for pending in takes {
            let take = Take(itemID: pending.itemID, itemTitle: pending.title, audioFileName: pending.file)
            take.sectionID = pending.sectionID
            take.rating = pending.rating
            take.session = session
            context.insert(take)
        }
        let now = Date()
        for warmup in warmups where completed.contains(warmup.id) { warmup.lastPracticed = now }
        for warmup in warmups where markedSolid.contains(warmup.id) { warmup.isSolid = true }
        for song in songs where completed.contains(song.id) { song.lastPracticed = now }
        // A section counts as practiced when its item was completed or got a take.
        for item in plan.items {
            guard let id = sectionID(item), completed.contains(item.id) || takes.contains(where: { $0.itemID == item.id }),
                  let section = songs.first(where: { $0.id == item.id })?.sections.first(where: { $0.sectionID == id })
            else { continue }
            section.lastPracticed = now
            if let rating = sectionRatings[id] { section.lastRating = rating.rawValue }
        }
        try? context.save()
    }
}

/// A take recorded this session, saved with the session.
struct PendingTake {
    var itemID: UUID
    var title: String
    var file: String
    var sectionID: String?
    var rating: String?
}
