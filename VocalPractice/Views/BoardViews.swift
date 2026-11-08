import SwiftData
import SwiftUI

/// Recent edits on the lesson board that the student hasn't dismissed yet.
struct NewFromBoardCard: View {
    let changes: [BoardMapping.Change]
    var onDone: () -> Void

    private var who: String {
        let names = Set(changes.map(\.who))
        return names.count == 1 ? names.first! : "your teacher"
    }

    var body: some View {
        Section {
            ForEach(changes.prefix(6)) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.text)
                    Text(change.date.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if changes.count > 6 {
                Text("And \(changes.count - 6) more").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Got it", action: onDone)
        } header: {
            Label("New from \(who)", systemImage: "sparkles")
        }
    }
}

/// Picks which of the teacher's routines plans the warmup half. "Automatic" goes by session length.
struct RoutinePickerSection: View {
    let routines: [BoardMapping.Routine]
    let minutes: Int
    @Binding var choice: String

    private var auto: BoardMapping.Routine? { BoardMapping.autoRoutine(routines, minutes: minutes) }
    private var current: BoardMapping.Routine? { BoardStore.routine(choice: choice, minutes: minutes, in: routines) }

    var body: some View {
        Section {
            Picker("Warmup routine", selection: $choice) {
                Text(auto.map { "Automatic: \($0.name)" } ?? "Automatic: rotate all").tag("")
                ForEach(routines) { Text($0.name).tag($0.id) }
            }
            if let missing = current?.missing, !missing.isEmpty {
                Label("Not found on the board: \(missing.joined(separator: ", "))", systemImage: "questionmark.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } footer: {
            Text("Routines come from your lesson board. Automatic uses the shortest numbered routine, or the longest one for 60 minutes.")
        }
    }
}

extension Data {
    /// Board state saved by BoardStore, read through @AppStorage so views refresh after a sync.
    func decoded<T: Decodable>(_ type: T.Type) -> T? { isEmpty ? nil : try? JSONDecoder().decode(type, from: self) }
}
