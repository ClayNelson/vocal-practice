import SwiftUI

/// Live pitch screen: the note you're singing, how sharp or flat, a scrolling pitch line,
/// and your held range for this sitting.
struct PitchView: View {
    @State private var tracker = PitchTracker()

    var body: some View {
        VStack(spacing: 16) {
            NoteReadout(midi: tracker.current)

            PitchGraph(history: tracker.history, seconds: tracker.historySeconds)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            RangeCard(range: tracker.range, reset: tracker.resetRange)

            if let error = tracker.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            Button {
                if tracker.isRunning { tracker.stop() } else { Task { await tracker.start() } }
            } label: {
                Label(tracker.isRunning ? "Stop" : "Start listening",
                      systemImage: tracker.isRunning ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isRunning ? .red : .indigo)
        }
        .padding()
        .navigationTitle("Pitch")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { tracker.stop() }
    }
}

private struct NoteReadout: View {
    let midi: Double?

    var body: some View {
        let note = midi.map(Note.init(midi:))
        VStack(spacing: 6) {
            Text(note?.label ?? "–")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(note == nil ? .secondary : .primary)
            CentsMeter(cents: note?.cents)
            Text(centsText(note)).font(.footnote).foregroundStyle(.secondary)
        }
        .animation(.snappy(duration: 0.15), value: note?.nearest)
    }

    private func centsText(_ note: Note?) -> String {
        guard let note else { return "Sing a note" }
        let c = Int(note.cents.rounded())
        if abs(c) <= 10 { return "In tune" }
        return c > 0 ? "\(c) cents sharp" : "\(-c) cents flat"
    }
}

/// Horizontal meter: center line is in tune, edges are a quarter tone off.
private struct CentsMeter: View {
    let cents: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Capsule().fill(.quaternary)
                Capsule().fill(.green.opacity(0.25)).frame(width: w * 0.2)
                Rectangle().fill(.secondary).frame(width: 1)
                if let cents {
                    let x = CGFloat(max(-50, min(50, cents)) / 50) * (w / 2 - 6)
                    Circle()
                        .fill(abs(cents) <= 10 ? Color.green : Color.orange)
                        .frame(width: 12, height: 12)
                        .offset(x: x)
                }
            }
        }
        .frame(width: 220, height: 12)
        .animation(.easeOut(duration: 0.08), value: cents)
    }
}

/// Scrolling pitch line over note lanes. The view follows your voice: it centers on your
/// recent pitch and shows about an octave and a fifth.
private struct PitchGraph: View {
    let history: [PitchTracker.Point]
    let seconds: Double
    private let span = 19.0

    var body: some View {
        Canvas { ctx, size in
            let voiced = history.compactMap(\.midi)
            let center = voiced.isEmpty ? 57.0 : voiced.suffix(60).sorted()[voiced.suffix(60).count / 2]
            let lowest = center - span / 2
            let y: (Double) -> CGFloat = { m in size.height * (1 - CGFloat((m - lowest) / span)) }

            // Note lanes: C and the natural notes labeled, sharps and flats shaded.
            for n in Int(lowest.rounded(.down))...Int((lowest + span).rounded(.up)) {
                let yy = y(Double(n))
                let isBlack = [1, 3, 6, 8, 10].contains(((n % 12) + 12) % 12)
                if isBlack {
                    let band = size.height / CGFloat(span)
                    ctx.fill(Path(CGRect(x: 0, y: yy - band / 2, width: size.width, height: band)),
                             with: .color(.primary.opacity(0.04)))
                } else {
                    var line = Path()
                    line.move(to: CGPoint(x: 34, y: yy))
                    line.addLine(to: CGPoint(x: size.width, y: yy))
                    ctx.stroke(line, with: .color(.primary.opacity(n % 12 == 0 ? 0.25 : 0.08)), lineWidth: 1)
                    ctx.draw(Text(Note.label(midi: n)).font(.caption2).foregroundColor(.secondary),
                             at: CGPoint(x: 16, y: yy))
                }
            }

            // Pitch line, broken wherever you weren't singing.
            guard let latest = history.last?.time else { return }
            let x: (Double) -> CGFloat = { t in 34 + (size.width - 34) * CGFloat(1 - (latest - t) / seconds) }
            var path = Path()
            var penDown = false
            for p in history {
                guard let m = p.midi else { penDown = false; continue }
                let pt = CGPoint(x: x(p.time), y: y(m))
                if penDown { path.addLine(to: pt) } else { path.move(to: pt); penDown = true }
            }
            ctx.stroke(path, with: .color(.indigo), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if let m = history.last?.midi {
                let pt = CGPoint(x: x(latest), y: y(m))
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 6, y: pt.y - 6, width: 12, height: 12)), with: .color(.indigo))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RangeCard: View {
    let range: RangeTracker
    let reset: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Range this sitting").font(.footnote).foregroundStyle(.secondary)
                if let low = range.low, let high = range.high {
                    Text("\(Note.label(midi: low)) to \(Note.label(midi: high))").font(.title3.bold())
                    Text("\(high - low) semitones, notes held ½ second").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Hold a note to start").font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Reset", action: reset).buttonStyle(.bordered)
                .disabled(range.low == nil)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack { PitchView() }
}
