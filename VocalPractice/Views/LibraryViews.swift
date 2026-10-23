import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: Warmups

struct WarmupsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Warmup.title) private var warmups: [Warmup]
    @State private var importTarget: Warmup?
    @State private var showingAdd = false
    @State private var syncMessage: String?

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
                            offsets.map { standalone[$0] }.forEach { context.delete($0) }
                        }
                }
            }
            .navigationTitle("Warmups")
            .refreshable { await syncFromTrello() }
            .safeAreaInset(edge: .bottom) {
                if let syncMessage {
                    Text(syncMessage).font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
                }
            }
            .toolbar { Button { showingAdd = true } label: { Image(systemName: "plus") } }
            .fileImporter(isPresented: Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } }),
                          allowedContentTypes: [.audio]) { result in
                if case .success(let url) = result, let target = importTarget,
                   let name = try? AudioStorage.importWarmup(from: url) {
                    target.audioFileName = name
                }
                importTarget = nil
            }
            .sheet(isPresented: $showingAdd) { AddWarmupSheet() }
        }
    }

    /// Pull to refresh: sync from Trello when connected; otherwise a no-op.
    private func syncFromTrello() async {
        guard TrelloSync.isConnected else { return }
        do {
            syncMessage = try await TrelloSync.run(context: context).summary
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    private func currentRung(_ group: String) -> Warmup? {
        let rungs = (ladders[group] ?? []).sorted { $0.ladderLevel < $1.ladderLevel }
        return rungs.first { !$0.isSolid } ?? rungs.last
    }

    private func row(_ warmup: Warmup, isCurrent: Bool) -> some View {
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
        .swipeActions(edge: .leading) {
            Button(warmup.isSolid ? "Not solid" : "Solid") { warmup.isSolid.toggle() }.tint(.green)
        }
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
            Section("Takes (\(takes.count))") {
                if takes.isEmpty { Text("Record takes during practice to hear progress.").foregroundStyle(.secondary) }
                ForEach(takes) { take in
                    Button {
                        if playingTake == take.id { player.stop(); playingTake = nil; return }
                        player.load(AudioStorage.takes.appending(path: take.audioFileName))
                        player.toggle(); playingTake = take.id
                    } label: {
                        Label(take.date.formatted(date: .abbreviated, time: .shortened),
                              systemImage: playingTake == take.id ? "stop.fill" : "play.fill")
                    }
                }
            }
        }
        .navigationTitle(song.title)
        .onDisappear { player.stop() }
    }
}

// MARK: Lessons

struct LessonsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lesson.date, order: .reverse) private var lessons: [Lesson]
    @AppStorage(Prefs.packageSize) private var packageSize = 30

    private var used: Int { lessons.filter { !$0.isGifted }.count }

    var body: some View {
        NavigationStack {
            List {
                Section("Package") {
                    LabeledContent("Lessons used", value: "\(used) of \(packageSize)")
                    LabeledContent("Remaining", value: "\(max(0, packageSize - used))")
                    ProgressView(value: Double(min(used, packageSize)), total: Double(packageSize))
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
    @Environment(\.modelContext) private var context
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

                TrelloSections()

                Section {
                    Button("Load Clay's starter set") {
                        SeedData.seedIfEmpty(context)
                        status = "Starter set loaded (only adds content when no warmups exist yet)."
                    }
                } header: {
                    Text("Sample content")
                } footer: {
                    Text("For demos: Clay's warmup names, songs, and lesson history. Skipped if you already have warmups.")
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
