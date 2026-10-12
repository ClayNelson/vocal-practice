import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: Warmups

struct WarmupsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Warmup.title) private var warmups: [Warmup]
    @State private var importTarget: Warmup?
    @State private var showingAdd = false

    private var ladders: [String: [Warmup]] {
        Dictionary(grouping: warmups.filter { $0.ladderGroup != nil }, by: { $0.ladderGroup! })
            .mapValues { $0.sorted { $0.ladderLevel < $1.ladderLevel } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ladders.keys.sorted(), id: \.self) { group in
                    Section("\(group) ladder") {
                        ForEach(ladders[group]!) { row($0, isCurrent: $0.id == currentRung(group)?.id) }
                    }
                }
                Section("Warmups") {
                    ForEach(warmups.filter { $0.ladderGroup == nil }) { row($0, isCurrent: false) }
                        .onDelete { offsets in
                            let standalone = warmups.filter { $0.ladderGroup == nil }
                            offsets.map { standalone[$0] }.forEach(delete)
                        }
                }
            }
            .navigationTitle("Warmups")
            .navigationDestination(for: Warmup.self) { WarmupDetailView(warmup: $0) }
            .toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            .fileImporter(isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
                          allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result, let target = importTarget {
                    target.replaceTrack(from: url)
                }
                importTarget = nil
            }
            .sheet(isPresented: $showingAdd) { AddWarmupSheet() }
        }
    }

    private func currentRung(_ group: String) -> Warmup? {
        let rungs = (ladders[group] ?? []).sorted { $0.ladderLevel < $1.ladderLevel }
        return rungs.first { !$0.isSolid } ?? rungs.last
    }

    private func delete(_ warmup: Warmup) {
        if let name = warmup.audioFileName { AudioStorage.remove(name, in: AudioStorage.warmups) }
        context.delete(warmup)
    }

    private func row(_ warmup: Warmup, isCurrent: Bool) -> some View {
        NavigationLink(value: warmup) {
            HStack {
                Image(systemName: warmup.isSolid ? "checkmark.circle.fill" : (isCurrent ? "arrow.right.circle.fill" : "circle"))
                    .foregroundStyle(warmup.isSolid ? .green : (isCurrent ? .indigo : .secondary))
                VStack(alignment: .leading) {
                    Text(warmup.title)
                    Text(warmup.audioFileName == nil ? "No track" : "Track ready")
                        .font(.caption).foregroundStyle(warmup.audioFileName == nil ? .orange : .secondary)
                }
                Spacer()
                Button { importTarget = warmup } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Import track for \(warmup.title)")
            }
        }
        .swipeActions(edge: .leading) {
            Button(warmup.isSolid ? "Not solid" : "Solid") { warmup.isSolid.toggle() }.tint(.green)
        }
    }
}

struct WarmupDetailView: View {
    @Bindable var warmup: Warmup
    @Query(sort: \Take.date, order: .reverse) private var allTakes: [Take]
    @State private var player = TrackPlayer()
    @State private var playingTake: UUID?
    @State private var trackLoaded = false
    @State private var importing = false

    private var takes: [Take] { allTakes.filter { $0.itemID == warmup.id } }
    private var playingTrack: Bool { playingTake == nil && player.isPlaying }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $warmup.title)
                Stepper("\(warmup.minutes) min per session", value: $warmup.minutes, in: 1...15)
                Toggle("Solid", isOn: $warmup.isSolid)
                if let group = warmup.ladderGroup {
                    LabeledContent("Ladder", value: warmup.ladderLevel == 0 ? group : "\(group) · \(warmup.ladderLevel)")
                }
                if let last = warmup.lastPracticed {
                    LabeledContent("Last practiced", value: last.formatted(date: .abbreviated, time: .omitted))
                }
                if !warmup.source.isEmpty { LabeledContent("Source", value: warmup.source) }
            }
            Section("Nicolette's track") {
                if let link = warmup.linkURL.flatMap(URL.init) {
                    Link(destination: link) { Label("Watch on YouTube", systemImage: "play.rectangle") }
                }
                if warmup.audioFileName != nil {
                    Button { toggleTrack() } label: {
                        Label(playingTrack ? "Pause" : "Play track", systemImage: playingTrack ? "pause.fill" : "play.fill")
                    }
                    if trackLoaded && playingTake == nil { ProgressView(value: player.progress) }
                }
                Button(warmup.audioFileName == nil ? "Import track from Files" : "Replace track") { importing = true }
            }
            TakesSection(takes: takes, player: player, playingTake: $playingTake)
        }
        .navigationTitle(warmup.title)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                player.stop(); trackLoaded = false
                warmup.replaceTrack(from: url)
            }
        }
        .onChange(of: playingTake) { if playingTake != nil { trackLoaded = false } }
        .onDisappear { player.stop() }
    }

    private func toggleTrack() {
        if playingTake != nil { player.stop(); playingTake = nil; trackLoaded = false }
        if !trackLoaded, let name = warmup.audioFileName {
            player.load(AudioStorage.warmups.appending(path: name))
            trackLoaded = true
        }
        player.toggle()
    }
}

struct AddWarmupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title = ""
    @State private var minutes = 4

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Stepper("\(minutes) minutes", value: $minutes, in: 1...15)
            }
            .navigationTitle("New warmup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(Warmup(title: title, minutes: minutes, source: "Added in app"))
                        dismiss()
                    }.disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: Songs

struct SongsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Song.title) private var songs: [Song]
    @State private var newSong: Song?

    var body: some View {
        NavigationStack {
            List {
                ForEach(SongStatus.allCases) { status in
                    let group = songs.filter { $0.status == status }
                    if !group.isEmpty {
                        Section(status.label) {
                            ForEach(group) { song in
                                NavigationLink(value: song) {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(song.title)
                                            if song.showcase { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                                        }
                                        Text([song.artist, song.key].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .onDelete { offsets in offsets.map { group[$0] }.forEach { context.delete($0) } }
                        }
                    }
                }
            }
            .navigationTitle("Songs")
            .navigationDestination(for: Song.self) { SongDetailView(song: $0) }
            .navigationDestination(item: $newSong) { SongDetailView(song: $0) }
            .toolbar {
                Button {
                    let song = Song(title: "New song")
                    context.insert(song)
                    newSong = song
                } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct SongDetailView: View {
    @Bindable var song: Song
    @Query(sort: \Take.date, order: .reverse) private var allTakes: [Take]
    @State private var player = TrackPlayer()
    @State private var playingTake: UUID?

    private var takes: [Take] { allTakes.filter { $0.itemID == song.id } }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $song.title)
                TextField("Artist", text: $song.artist)
                TextField("Key (e.g. G, Bb)", text: $song.key)
                Picker("Status", selection: Binding(get: { song.status }, set: { song.status = $0 })) {
                    ForEach(SongStatus.allCases) { Text($0.label).tag($0) }
                }
                Stepper("\(song.minutes) min per session", value: $song.minutes, in: 2...20)
                Toggle("Showcase song", isOn: $song.showcase)
                TextField("MyOps path", text: $song.myOpsPath)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section("Practice notes") {
                TextField("From lessons, what to fix", text: $song.notes, axis: .vertical).lineLimit(2...8)
            }
            Section("Lyrics") {
                TextField("Paste lyrics", text: $song.lyrics, axis: .vertical).lineLimit(4...20)
            }
            TakesSection(takes: takes, player: player, playingTake: $playingTake)
        }
        .navigationTitle(song.title)
        .onDisappear { player.stop() }
    }
}

// MARK: Lessons

struct LessonsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lesson.date, order: .reverse) private var lessons: [Lesson]
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @AppStorage(Prefs.packageSize) private var packageSize = 30

    private var used: Int { lessons.filter { !$0.isGifted }.count }
    private var sinceLastLesson: [PracticeSession] {
        PracticeReview.sinceLastLesson(sessions, date: \.date, lastLesson: lessons.first?.date)
    }
    private var daysSinceLastLesson: Int {
        Set(sinceLastLesson.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Package") {
                    LabeledContent("Lessons used", value: "\(used) of \(packageSize)")
                    LabeledContent("Remaining", value: "\(max(0, packageSize - used))")
                    ProgressView(value: Double(min(used, packageSize)), total: Double(packageSize))
                }
                Section("Since last lesson") {
                    LabeledContent("Practice days", value: "\(daysSinceLastLesson)")
                    let noted = sinceLastLesson.filter { !$0.notes.isEmpty }
                    if noted.isEmpty {
                        Text("Notes you save after a session show up here, ready for Nicolette.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(noted) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.notes)
                            Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("History") {
                    ForEach(lessons) { lesson in
                        NavigationLink {
                            LessonDetailView(lesson: lesson)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(lesson.isGifted ? "Gifted lesson" : "Lesson \(lesson.number)")
                                Text(lesson.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in offsets.map { lessons[$0] }.forEach { context.delete($0) } }
                }
            }
            .navigationTitle("Lessons")
            .toolbar {
                Button {
                    context.insert(Lesson(date: .now, number: used + 1))
                } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct LessonDetailView: View {
    @Bindable var lesson: Lesson
    var body: some View {
        Form {
            DatePicker("Date", selection: $lesson.date, displayedComponents: .date)
            Stepper("Lesson \(lesson.number)", value: $lesson.number, in: 0...200)
            Toggle("Gifted / makeup", isOn: $lesson.isGifted)
            Section("Nicolette's notes") {
                TextField("What she worked on, homework", text: $lesson.notes, axis: .vertical).lineLimit(4...20)
            }
        }
        .navigationTitle("Lesson")
    }
}

// MARK: Settings

struct SettingsView: View {
    @AppStorage(Prefs.daysPerWeek) private var daysPerWeek = 4
    @AppStorage(Prefs.reminderHour) private var hour = 18
    @AppStorage(Prefs.reminderMinute) private var minute = 30
    @AppStorage(Prefs.reminderDays) private var daysRaw = "2,3,5,6"   // Mon, Tue, Thu, Fri
    @AppStorage(Prefs.packageSize) private var packageSize = 30
    @State private var status: String?

    private var days: Set<Int> { Set(daysRaw.split(separator: ",").compactMap { Int($0) }) }
    private let symbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(daysPerWeek) days a week", value: $daysPerWeek, in: 3...5)
                    Text("Nicolette's plan: \(daysPerWeek) days at \(SessionPlanner.defaultMinutes(daysPerWeek: daysPerWeek)) minutes, half warmups and half songs.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Practice plan") }

                Section("Reminders") {
                    DatePicker("Time", selection: Binding(get: { timeDate }, set: setTime), displayedComponents: .hourAndMinute)
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let on = days.contains(day)
                            Button(String(symbols[day - 1].prefix(2))) { toggle(day) }
                                .buttonStyle(.bordered).tint(on ? .indigo : .gray)
                                .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    Button("Save reminders") { Task { await saveReminders() } }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("Lessons") {
                    Stepper("Package: \(packageSize) lessons", value: $packageSize, in: 1...100)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var timeDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private func setTime(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 18; minute = parts.minute ?? 30
    }

    private func toggle(_ day: Int) {
        var set = days
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        daysRaw = set.sorted().map(String.init).joined(separator: ",")
    }

    private func saveReminders() async {
        guard await ReminderScheduler.requestAuthorization() else {
            status = "Notifications are off. Enable them in iOS Settings."
            return
        }
        await ReminderScheduler.schedule(weekdays: days, hour: hour, minute: minute,
                                         minutes: SessionPlanner.defaultMinutes(daysPerWeek: daysPerWeek))
        status = "Reminders set for \(days.count) days a week."
    }
}
