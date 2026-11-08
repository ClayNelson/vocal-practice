import SwiftData
import SwiftUI

struct TodayView: View {
    @Query private var warmups: [Warmup]
    @Query private var songs: [Song]
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]
    @Query(sort: \Lesson.date, order: .reverse) private var lessons: [Lesson]

    @AppStorage(Prefs.daysPerWeek) private var daysPerWeek = 4
    @State private var minutes: Int?
    @State private var voiceCondition = 3
    @State private var activePlan: IdentifiedPlan?

    private var sessionMinutes: Int { minutes ?? SessionPlanner.defaultMinutes(daysPerWeek: daysPerWeek) }
    private var daysThisWeek: Int { WeeklyProgress.daysPracticed(sessionDates: sessions.map(\.date)) }
    private var practicedToday: Bool { sessions.contains { Calendar.current.isDateInToday($0.date) } }

    private var plan: SessionPlan {
        SessionPlanner.plan(minutes: sessionMinutes,
                            warmups: warmups.map(\.snapshot),
                            songs: songs.map { $0.snapshot(on: .now, fullRunsThisWeek: fullRunsThisWeek($0)) },
                            voiceCondition: voiceCondition)
    }

    /// Days this week the song was completed in a session; caps maintenance at 3 full runs.
    private func fullRunsThisWeek(_ song: Song) -> Int {
        WeeklyProgress.daysPracticed(sessionDates: sessions.filter { $0.completedItemIDs.contains(song.id) }.map(\.date))
    }

    /// The song whose goal is soonest, among plans not yet past their goal.
    private var activeGoal: (song: Song, plan: SongPlan)? {
        let today = PlanDate.today()
        return songs.compactMap { song in PlanStore.currentPlan(for: song).map { (song: song, plan: $0) } }
            .filter { $0.plan.goal.date >= today }
            .min { $0.plan.goal.date < $1.plan.goal.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 20) {
                        WeekRing(done: daysThisWeek, target: daysPerWeek)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(daysThisWeek) of \(daysPerWeek) days").font(.title2.bold())
                            Text(practicedToday ? "Practiced today" : "Not yet today")
                                .foregroundStyle(practicedToday ? .green : .secondary)
                            if let last = lessons.first {
                                Text("Last lesson \(last.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                if let goal = activeGoal {
                    Section { GoalCard(song: goal.song, plan: goal.plan, today: .today()) }
                }

                Section("How's your voice?") {
                    Picker("Voice", selection: $voiceCondition) {
                        ForEach(1...5, id: \.self) { Text(voiceConditionLabel($0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if voiceCondition <= 2 {
                        Text("Gentle session: lighter song block, one rung lower on ladders.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Session length") {
                    Picker("Minutes", selection: Binding(get: { sessionMinutes }, set: { minutes = $0 })) {
                        ForEach([30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Warmups (\(minutesOf(plan.warmups)) min)") {
                    ForEach(plan.warmups, id: \.id) { PlanRow(item: $0) }
                }
                Section("Songs (\(minutesOf(plan.songs)) min)") {
                    if plan.songs.isEmpty {
                        Text("Add a song in Learning or Polishing to fill this half.").foregroundStyle(.secondary)
                    }
                    ForEach(plan.songs, id: \.id) { PlanRow(item: $0) }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { PitchView() } label: {
                        Label("Pitch", systemImage: "tuningfork")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SessionHistoryView() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Session history")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { activePlan = IdentifiedPlan(plan: plan) } label: {
                    Label("Start \(sessionMinutes)-minute session", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .disabled(plan.items.isEmpty)
            }
            .fullScreenCover(item: $activePlan) { wrapped in
                SessionPlayerView(plan: wrapped.plan, voiceCondition: voiceCondition)
            }
        }
    }

    private func minutesOf(_ items: [PlanItem]) -> Int { items.reduce(0) { $0 + $1.minutes } }
}

struct IdentifiedPlan: Identifiable {
    let id = UUID()
    let plan: SessionPlan
}

struct PlanRow: View {
    let item: PlanItem
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.indigo).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let mode = item.songMode?.label {
                    Text(mode).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(item.minutes) min").foregroundStyle(.secondary).monospacedDigit()
        }
    }
    private var icon: String {
        if case .warmup = item { return "waveform" } else { return "music.note" }
    }
}

struct WeekRing: View {
    let done: Int
    let target: Int
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: min(1, Double(done) / Double(max(target, 1))))
                .stroke(done >= target ? Color.green : .indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: done >= target ? "checkmark" : "music.mic").font(.title3)
        }
        .frame(width: 64, height: 64)
        .accessibilityLabel("\(done) of \(target) practice days this week")
    }
}
