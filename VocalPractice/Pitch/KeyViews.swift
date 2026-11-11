import SwiftData
import SwiftUI

/// Key mode on the pitch screen: the key you're singing in, live, and which key options suit your voice.
struct KeyPanel: View {
    let finder: KeyFinder
    let current: Double?
    let range: RangeTracker
    let reset: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                KeyRing(weights: finder.weights, current: current.map { Int($0.rounded()) }, key: shownKey)
                    .frame(height: 240)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(verdictText)

                VStack(spacing: 4) {
                    Text(verdictText).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(detailText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                HStack {
                    ProgressView(value: min(finder.seconds, finder.settleAfter), total: finder.settleAfter)
                    Text("\(Int(finder.seconds)) s").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Button("Reset", action: reset).buttonStyle(.bordered).disabled(finder.seconds == 0)
                }

                KeyFitCard(found: shownKey, range: range)
            }
        }
    }

    private var shownKey: KeyFinder.Candidate? {
        switch finder.verdict {
        case .listening: nil
        case .leaning(let key), .settled(let key), .relatives(let key, _): key
        }
    }

    private var verdictText: String {
        switch finder.verdict {
        case .listening: finder.seconds == 0 ? "Sing a song or a phrase" : "Keep singing"
        case .leaning(let key): "Probably \(key.name)"
        case .settled(let key): key.name
        case .relatives(let a, let b): "\(a.name) or \(b.name)"
        }
    }

    private var detailText: String {
        switch finder.verdict {
        case .listening:
            "Hold notes as you go. A verse and a chorus is usually enough."
        case .relatives:
            "These share the same notes. Which one feels like home (where the song wants to end) tells them apart."
        case .leaning, .settled:
            "Also close: " + finder.candidates.dropFirst().prefix(2).map(\.name).joined(separator: ", ")
        }
    }
}

/// The 12 notes around the circle of fifths, brighter the longer you've held them.
/// A key's notes sit in one connected arc, outlined once a key is found.
struct KeyRing: View {
    let weights: [Double]
    let current: Int?
    let key: KeyFinder.Candidate?

    /// C, G, D, A, E, B, F♯, C♯, A♭, E♭, B♭, F.
    static let fifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 26
            let most = max(weights.max() ?? 0, 0.001)
            let inKey = key.map { KeyFinder.scale(tonic: $0.tonic, isMinor: $0.isMinor) } ?? []
            let singing = current.map { (($0 % 12) + 12) % 12 }

            for (index, pc) in Self.fifths.enumerated() {
                let angle = Double(index) / 12 * 2 * .pi - .pi / 2
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                let dot = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
                let strength = weights[pc] / most
                ctx.fill(Path(ellipseIn: dot), with: .color(.indigo.opacity(0.08 + 0.8 * strength)))
                if inKey.contains(pc) {
                    ctx.stroke(Path(ellipseIn: dot.insetBy(dx: 1.5, dy: 1.5)), with: .color(.indigo), lineWidth: 3)
                }
                if pc == key?.tonic {
                    ctx.stroke(Path(ellipseIn: dot.insetBy(dx: -4, dy: -4)), with: .color(.indigo), lineWidth: 2)
                }
                if pc == singing {
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: dot.maxY + 2, width: 10, height: 10)), with: .color(.orange))
                }
                ctx.draw(Text(Note.names[pc]).font(.headline)
                            .foregroundColor(strength > 0.55 ? .white : .primary), at: point)
            }
            if let key {
                ctx.draw(Text(key.name).font(.title3.bold()), at: center)
            }
        }
    }
}

/// Which of a song's key options suits the range you held this sitting.
struct KeyFitCard: View {
    let found: KeyFinder.Candidate?
    let range: RangeTracker

    @Environment(\.modelContext) private var context
    @Query(sort: \Song.title) private var songs: [Song]
    @State private var songID: UUID?
    @State private var applied: String?

    private var rangedSongs: [Song] {
        songs.filter { $0.rangeLowMidi != nil && $0.rangeHighMidi != nil && NoteName.key($0.originalKey ?? "") != nil }
    }
    private var song: Song? { rangedSongs.first { $0.id == songID } ?? rangedSongs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which key suits your voice").font(.headline)
            if let song, let low = song.rangeLowMidi, let high = song.rangeHighMidi, let original = song.originalKey {
                Picker("Song", selection: Binding(get: { song.id }, set: { songID = $0; applied = nil })) {
                    ForEach(rangedSongs) { Text($0.title).tag($0.id) }
                }
                if let userHigh = range.high {
                    ForEach(options(song, original: original, low: low, high: high, userHigh: userHigh), id: \.key) { option in
                        HStack(alignment: .top) {
                            Image(systemName: option.fits ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(option.fits ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.key + (option.key == found?.planKey ? "  (what you sang)" : "")).font(.subheadline.bold())
                                Text(option.summary(userHigh: userHigh)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Hold your highest comfortable note for half a second, then your lowest. The range card on Pitch mode shows what's counted.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let found {
                    Button(applied == found.planKey ? "Set \(song.title) to \(found.planKey)" : "Use \(found.planKey) for \(song.title)") {
                        use(found.planKey, for: song)
                    }
                    .buttonStyle(.bordered)
                    .disabled(applied == found.planKey)
                }
            } else {
                Text("Give a song a plan with its range (like E3 to F#4) to compare keys here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    /// The plan's key options, plus the key you sang if it isn't one of them.
    private func options(_ song: Song, original: String, low: Int, high: Int, userHigh: Int) -> [KeyFit.Option] {
        var keys = song.keyOptionsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if keys.isEmpty { keys = [original] }
        if let found, !found.isMinor, !keys.contains(found.planKey) { keys.append(found.planKey) }
        return KeyFit.options(originalKey: original, keys: keys, songLow: low, songHigh: high,
                              userLow: range.low, userHigh: userHigh)
    }

    /// Sets the song's key and moves it to the front of the plan's key options (the current pick).
    private func use(_ key: String, for song: Song) {
        song.key = key
        if var plan = PlanStore.currentPlan(for: song) {
            plan.song.keyOptions.removeAll { $0 == key }
            plan.song.keyOptions.insert(key, at: 0)
            try? PlanStore.apply(plan, to: song, in: context)
        }
        try? context.save()
        applied = key
    }
}
