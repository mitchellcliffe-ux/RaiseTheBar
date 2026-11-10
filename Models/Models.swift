import Foundation
import SwiftData

// MARK: - Plain enums

/// The three groups the plan adapts (named TrainingGroup so it never clashes with SwiftUI.Group). Each group has its own running adjustment.
enum TrainingGroup: String, Codable, CaseIterable, Identifiable {
    case easy, threshold, vo2
    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: return "Easy running"
        case .threshold: return "Threshold work"
        case .vo2: return "VO2max and speed work"
        }
    }

    /// How hard (RPE 1 to 10) a normal session in this group should feel.
    var targetRPE: Double {
        switch self {
        case .easy: return 3.5
        case .threshold: return 6.5
        case .vo2: return 8
        }
    }

    /// Largest total change allowed, in % of speed. Up = faster than the base pace, down = slower.
    var capUp: Double {
        switch self {
        case .easy: return 3
        case .threshold: return 3
        case .vo2: return 4
        }
    }
    var capDown: Double {
        switch self {
        case .easy: return 5
        case .threshold: return 5
        case .vo2: return 6
        }
    }
    /// Easy running moves in smaller steps than the hard groups.
    var stepScale: Double { self == .easy ? 0.5 : 1.0 }
}

enum Load: String, Codable { case easy, medium, hard }

enum Evidence: String, Codable {
    case study = "Study"        // that exact format was tested in a published trial
    case practice = "Practice"  // standard coaching, no trial of its own
}

/// Pace zones. Every pace in the app comes from one benchmark (see PaceEngine).
enum Zone: String, Codable, CaseIterable, Identifiable {
    case recovery, easy, steady, goal, threshold, interval, repetition
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recovery: return "Recovery"
        case .easy: return "Easy"
        case .steady: return "Steady"
        case .goal: return "Goal pace"
        case .threshold: return "Threshold"
        case .interval: return "Interval (VO2max)"
        case .repetition: return "Repetition (fast)"
        }
    }
}

enum SessionStatus: String, Codable { case planned, done, skipped }

enum TrainingStyle: String, Codable, CaseIterable, Identifiable {
    case balanced, polarised, norwegian
    var id: String { rawValue }
    var label: String {
        switch self {
        case .balanced: return "Let the app choose"
        case .polarised: return "Mostly easy, a little very hard (80/20)"
        case .norwegian: return "Norwegian-style, threshold heavy"
        }
    }
}

enum Gut: String, Codable, CaseIterable, Identifiable {
    case sensitive, normal, robust
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sensitive: return "Sensitive stomach"
        case .normal: return "Normal"
        case .robust: return "Handles fuel well"
        }
    }
}

enum Surface: String, Codable, CaseIterable, Identifiable {
    case road, trail, treadmill, mixed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Every session the app knows how to build. The details live in SessionLibrary.
enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case easy, strides, recovery, longRun, openers
    case lightThreshold, cruise, overUnders, norwegianThreshold, hillAttacks
    case longReps, norwegian4x4, vo2Reps, thirtyFifteen, hillRepeats
    case hillSprints, fartlek, goalPace, leadKick
    case test30, test3k, race, strength
    var id: String { rawValue }
}

// MARK: - Stored models

@Model
final class RunnerProfile {
    var setupDone: Bool = false

    // Basics
    var name: String = ""
    var age: Int = 35
    var weightKg: Double = 70
    var heightCm: Double = 175
    var useMiles: Bool = false
    var maxHR: Int = 0          // 0 = not set
    var restingHR: Int = 0

    // Experience
    var yearsRunning: Double = 1
    var currentRunsPerWeek: Int = 3
    var weeklyMinutes: Int = 120
    var longestRunMinutes: Int = 45
    var recentBreak: Bool = false

    // Goal
    var goalDistanceKm: Double = 10
    var goalSeconds: Double = 0         // 0 = no time goal
    var hasRaceDate: Bool = false
    var raceDate: Date = Date()

    // Benchmark (one recent effort drives every pace)
    var benchmarkKnown: Bool = false
    var benchmarkDistanceM: Double = 5000
    var benchmarkSeconds: Double = 0
    var vdot: Double = 35

    // Preferences
    var styleRaw: String = TrainingStyle.balanced.rawValue
    var availableDays: [Int] = [1, 3, 5, 6]     // 0 = Monday ... 6 = Sunday
    var longRunDay: Int = 6
    var runsPerWeekWanted: Int = 4
    var surfaceRaw: String = Surface.road.rawValue
    var doesStrength: Bool = false
    var gutRaw: String = Gut.normal.rawValue
    var usesCaffeine: Bool = true
    var diet: String = ""
    var injuries: String = ""
    var hasShiftWork: Bool = false

    // Plan bookkeeping
    var planStart: Date = Date()
    var weekOffset: Int = 0                     // weeks already used by earlier 12-week plans
    var adaptFrom: Date = Date.distantPast      // "reset adaptation" moves this forward
    var overridesJSON: String = ""              // {"easy": 330, "threshold": 255} in seconds per km

    // Safety screen
    var readinessAccepted: Bool = false

    init() {}

    var style: TrainingStyle {
        get { TrainingStyle(rawValue: styleRaw) ?? .balanced }
        set { styleRaw = newValue.rawValue }
    }
    var gut: Gut {
        get { Gut(rawValue: gutRaw) ?? .normal }
        set { gutRaw = newValue.rawValue }
    }
    var surface: Surface {
        get { Surface(rawValue: surfaceRaw) ?? .road }
        set { surfaceRaw = newValue.rawValue }
    }

    var overrides: [Zone: Double] {
        get {
            guard let data = overridesJSON.data(using: .utf8),
                  let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
            var out: [Zone: Double] = [:]
            for (k, v) in raw { if let z = Zone(rawValue: k) { out[z] = v } }
            return out
        }
        set {
            var raw: [String: Double] = [:]
            for (z, v) in newValue { raw[z.rawValue] = v }
            if let data = try? JSONEncoder().encode(raw), let s = String(data: data, encoding: .utf8) {
                overridesJSON = s
            }
        }
    }
}

/// What the note on a run said, after it was read. Stored with the session.
struct FeedbackRead: Codable, Hashable {
    var text: String            // the note as it was when read (a stale read is ignored)
    var dev: Double             // extra effort gap in RPE points, -1 to +1.5, steps of 0.5
    var cutPct: Double?         // how much slower than planned, as a fraction (0.04 = 4%)
    var cutFromSec: Double?     // pace he dropped from (seconds per km), if he said so
    var cutToSec: Double?
    var ease: Bool
    var fail: Bool
    var off: Bool               // blames something outside the training
    var cause: String?
    var summary: String
}

@Model
final class PlanSession {
    var id: UUID = UUID()
    var week: Int = 1
    var day: Int = 0                    // 0 = Monday
    var date: Date = Date()
    var kindRaw: String = SessionKind.easy.rawValue
    var plannedMinutes: Int = 30
    var progress: Double = 0            // 0...1 position inside its block; sets how big the session is
    var statusRaw: String = SessionStatus.planned.rawValue
    var isExtra: Bool = false

    // What happened
    var rpe: Int?
    var actualMinutes: Int?
    var actualKm: Double?
    var avgHR: Int?
    var note: String = ""
    var noteIgnored: Bool = false
    var pain: Bool = false
    var feedback: FeedbackRead?
    var healthKitUUID: String?

    init(week: Int, day: Int, date: Date, kind: SessionKind, minutes: Int, progress: Double, isExtra: Bool = false) {
        self.week = week
        self.day = day
        self.date = date
        self.kindRaw = kind.rawValue
        self.plannedMinutes = minutes
        self.progress = progress
        self.isExtra = isExtra
    }

    var kind: SessionKind {
        get { SessionKind(rawValue: kindRaw) ?? .easy }
        set { kindRaw = newValue.rawValue }
    }
    var status: SessionStatus {
        get { SessionStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    var group: TrainingGroup? { SessionLibrary.info(kind).group }
}

/// One benchmark result: a race or time trial. Kept so progress can be charted.
@Model
final class BenchmarkEntry {
    var date: Date = Date()
    var distanceM: Double = 5000
    var seconds: Double = 0
    var vdot: Double = 0
    var source: String = ""

    init(date: Date, distanceM: Double, seconds: Double, vdot: Double, source: String) {
        self.date = date
        self.distanceM = distanceM
        self.seconds = seconds
        self.vdot = vdot
        self.source = source
    }
}
