import SwiftUI
import SwiftData
import Charts

extension Color {
    /// The orange from the logo.
    static let brand = Color(red: 0.91, green: 0.35, blue: 0.05)
}

/// Green at 1, red at 10.
func rpeColor(_ v: Int) -> Color {
    Color(hue: (1 - Double(v - 1) / 9.0) * 0.38, saturation: 0.75, brightness: 0.85)
}

// MARK: - Effort buttons

struct RPEPicker: View {
    @Binding var value: Int?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(1...10, id: \.self) { v in
                Button {
                    value = (value == v) ? nil : v
                } label: {
                    Text("\(v)")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(rpeColor(v).opacity(value == v ? 1 : 0.25))
                        .foregroundStyle(value == v ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effort \(v) out of 10")
                .accessibilityAddTraits(value == v ? .isSelected : [])
            }
        }
    }
}

// MARK: - Step chart

struct StepChart: View {
    let steps: [Step]
    let paces: Paces
    let miles: Bool

    private struct Bar: Identifiable {
        let id = UUID()
        let start: Double
        let end: Double
        let speed: Double
        let zone: String
    }

    private var bars: [Bar] {
        var t = 0.0
        var out: [Bar] = []
        for s in steps {
            let minutes = Double(s.seconds) / 60
            let kmh = 3600 / paces.pace(s.zone, mult: s.mult)
            out.append(Bar(start: t, end: t + minutes, speed: miles ? kmh / 1.609344 : kmh, zone: s.zone.label))
            t += minutes
        }
        return out
    }

    var body: some View {
        let lowest = (bars.map { $0.speed }.min() ?? 6) * 0.7
        Chart(bars) { b in
            RectangleMark(xStart: .value("Start", b.start),
                          xEnd: .value("End", b.end),
                          yStart: .value("Base", lowest),
                          yEnd: .value("Speed", b.speed))
                .foregroundStyle(by: .value("Zone", b.zone))
        }
        .chartXAxisLabel("minutes")
        .chartYAxisLabel(miles ? "mph" : "km/h")
        .chartLegend(position: .bottom, spacing: 8)
        .frame(height: 190)
        .accessibilityLabel("Chart of the session: speed against time")
    }
}

// MARK: - Time entry

/// Hours, minutes and seconds in three small boxes, bound to a number of seconds.
struct TimeField: View {
    @Binding var seconds: Double

    private var h: Binding<Int> {
        Binding(get: { Int(seconds) / 3600 }, set: { seconds = Double($0 * 3600 + (Int(seconds) % 3600)) })
    }
    private var m: Binding<Int> {
        Binding(get: { (Int(seconds) % 3600) / 60 }, set: { seconds = Double((Int(seconds) / 3600) * 3600 + $0 * 60 + Int(seconds) % 60) })
    }
    private var s: Binding<Int> {
        Binding(get: { Int(seconds) % 60 }, set: { seconds = Double((Int(seconds) / 60) * 60 + $0) })
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField("h", value: h, format: .number).keyboardType(.numberPad).frame(width: 36).multilineTextAlignment(.trailing)
            Text(":")
            TextField("mm", value: m, format: .number).keyboardType(.numberPad).frame(width: 36).multilineTextAlignment(.trailing)
            Text(":")
            TextField("ss", value: s, format: .number).keyboardType(.numberPad).frame(width: 36).multilineTextAlignment(.trailing)
        }
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: - Plan helpers

enum PlanHelpers {
    /// Week number a date belongs to, using the weeks already in the plan.
    static func week(for date: Date, sessions: [PlanSession], profile: RunnerProfile) -> Int {
        let monday = PlanGenerator.mondayOf(date)
        if let s = sessions.first(where: { PlanGenerator.mondayOf($0.date) == monday }) { return s.week }
        let firstMonday = PlanGenerator.mondayOnOrAfter(profile.planStart)
        let weeks = Calendar.current.dateComponents([.day], from: firstMonday, to: monday).day.map { $0 / 7 } ?? 0
        return profile.weekOffset + max(1, weeks + 1)
    }

    static func context(_ profile: RunnerProfile) -> BuildContext {
        BuildContext(goalKm: max(profile.goalDistanceKm, 1), vdot: profile.vdot)
    }

    static func estimatedKm(_ steps: [Step], paces: Paces) -> Double {
        steps.reduce(0.0) { $0 + Double($1.seconds) / paces.pace($1.zone, mult: $1.mult) }
    }

    /// A readable list of what to do, one entry per segment.
    struct Line: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
    }

    static func lines(_ segments: [Segment], paces: Paces, profile: RunnerProfile) -> [Line] {
        func target(_ s: Step) -> String {
            if s.zone == .recovery && !s.work { return "very easy" }
            let p = paces.pace(s.zone, mult: s.mult)
            var t = s.zone == .easy
                ? Fmt.paceRange(p, upTo: 1.10, miles: profile.useMiles)
                : Fmt.pace(p, miles: profile.useMiles)
            if s.byEffort { t += ", by effort" }
            if profile.maxHR > 0, let band = PaceEngine.hrBand(s.zone) {
                t += " · HR \(Int(Double(profile.maxHR) * band.0))–\(Int(Double(profile.maxHR) * band.1))"
            }
            return t
        }
        var out: [Line] = []
        for seg in segments {
            switch seg {
            case .single(let s):
                out.append(Line(title: "\(Fmt.seconds(s.seconds)) \(s.label.lowercased())", detail: target(s)))
            case .reps(let title, let count, let steps):
                let detail = steps.map { "\(Fmt.seconds($0.seconds)) \($0.label.lowercased()), \(target($0))" }.joined(separator: "\nthen ")
                out.append(Line(title: "\(count) × \(title.lowercased())", detail: detail))
            }
        }
        return out
    }
}
