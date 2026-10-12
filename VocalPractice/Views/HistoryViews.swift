import SwiftData
import SwiftUI

/// Past sessions, newest first. Deleting a session also removes its take recordings.
struct SessionHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "music.mic",
                                       description: Text("Finish a session on the Today tab and it shows up here."))
            }
            ForEach(sessions) { session in
                NavigationLink { SessionDetailView(session: session) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(voiceConditionLabel(session.voiceCondition)).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("^[\(session.completedItemIDs.count) item](inflect: true) · \(session.plannedMinutes) min · ^[\(session.takes.count) take](inflect: true)")
                            .font(.caption).foregroundStyle(.secondary)
                        if !session.notes.isEmpty { Text(session.notes).font(.footnote).lineLimit(2) }
                    }
                }
            }
            .onDelete { offsets in offsets.map { sessions[$0] }.forEach(delete) }
        }
        .navigationTitle("History")
    }

    private func delete(_ session: PracticeSession) {
        session.takes.forEach { AudioStorage.remove($0.audioFileName, in: AudioStorage.takes) }
        context.delete(session)
    }
}

struct SessionDetailView: View {
    @Bindable var session: PracticeSession
    @Query private var warmups: [Warmup]
    @Query private var songs: [Song]
    @State private var player = TrackPlayer()
    @State private var playingTake: UUID?

    /// Titles of completed items that still exist; takes keep their own titles.
    private var completedTitles: [String] {
        let ids = Set(session.completedItemIDs)
        return warmups.filter { ids.contains($0.id) }.map(\.title) + songs.filter { ids.contains($0.id) }.map(\.title)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Date", value: session.date.formatted(date: .long, time: .shortened))
                LabeledContent("Planned", value: "\(session.plannedMinutes) min")
                Picker("Voice", selection: $session.voiceCondition) {
                    ForEach(1...5, id: \.self) { Text(voiceConditionLabel($0)).tag($0) }
                }
            }
            Section("Completed (\(completedTitles.count))") {
                if completedTitles.isEmpty { Text("Nothing marked done.").foregroundStyle(.secondary) }
                ForEach(Array(completedTitles.enumerated()), id: \.offset) { Text($0.element) }
            }
            Section("Notes for next lesson") {
                TextField("What felt good, what's stuck", text: $session.notes, axis: .vertical).lineLimit(3...8)
            }
            TakesSection(takes: session.takes.sorted { $0.date > $1.date }, player: player,
                         playingTake: $playingTake, showsTitle: true)
        }
        .navigationTitle("Session")
        .onDisappear { player.stop() }
    }
}

/// Playable list of takes with swipe to delete (removes the audio file too).
/// Shared by song, warmup and session detail screens.
struct TakesSection: View {
    let takes: [Take]
    let player: TrackPlayer
    @Binding var playingTake: UUID?
    var showsTitle = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Section("Takes (\(takes.count))") {
            if takes.isEmpty {
                Text("Record takes during practice to hear progress.").foregroundStyle(.secondary)
            }
            ForEach(takes) { take in
                let active = playingTake == take.id && player.isPlaying
                Button {
                    if playingTake == take.id { player.stop(); playingTake = nil; return }
                    player.load(AudioStorage.takes.appending(path: take.audioFileName))
                    player.toggle()
                    playingTake = take.id
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: active ? "stop.fill" : "play.fill").frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            if showsTitle { Text(take.itemTitle) }
                            Text(take.date.formatted(date: .abbreviated, time: .shortened))
                                .font(showsTitle ? .caption : .body)
                                .foregroundStyle(showsTitle ? .secondary : .primary)
                            if active { ProgressView(value: player.progress) }
                        }
                    }
                }
                .accessibilityLabel(active ? "Stop take" : "Play take from \(take.date.formatted(date: .abbreviated, time: .shortened))")
            }
            .onDelete { offsets in
                for take in offsets.map({ takes[$0] }) {
                    if playingTake == take.id { player.stop(); playingTake = nil }
                    AudioStorage.remove(take.audioFileName, in: AudioStorage.takes)
                    context.delete(take)
                }
            }
        }
    }
}

/// Shared 1 to 5 voice check-in labels.
func voiceConditionLabel(_ value: Int) -> String {
    ["Rough", "Tired", "OK", "Good", "Great"][max(1, min(5, value)) - 1]
}
