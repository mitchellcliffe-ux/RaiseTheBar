import Foundation
import HealthKit

#if canImport(WorkoutKit)
import WorkoutKit

/// Sends a session to the Apple Watch Workout app as a structured workout (warm-up, reps, cool-down), using WorkoutKit.
///
/// This version sets time goals only. Pace alerts are left out on purpose: the alert types are the part of WorkoutKit I am least
/// sure of, so add a pace-range alert to each interval step once you have checked Apple's current WorkoutKit documentation.
/// The target pace is shown in the session screen and in the copied text.
enum WatchExport {

    enum ExportError: LocalizedError {
        case notAuthorized
        case nothingToSend
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Workouts were not allowed. Turn them on in Settings, then try again."
            case .nothingToSend: return "This session has no running steps to send."
            }
        }
    }

    static func customWorkout(name: String, segments: [Segment], outdoor: Bool) -> CustomWorkout? {
        var segs = segments
        var warmup: WorkoutStep?
        var cooldown: WorkoutStep?

        if case .single(let s)? = segs.first, s.label.lowercased().contains("warm") {
            warmup = WorkoutStep(goal: .time(Double(s.seconds), .seconds))
            segs.removeFirst()
        }
        if case .single(let s)? = segs.last, s.label.lowercased().contains("cool") {
            cooldown = WorkoutStep(goal: .time(Double(s.seconds), .seconds))
            segs.removeLast()
        }

        var blocks: [IntervalBlock] = []
        for seg in segs {
            switch seg {
            case .single(let s):
                let step = IntervalStep(.work, step: WorkoutStep(goal: .time(Double(s.seconds), .seconds)))
                blocks.append(IntervalBlock(steps: [step], iterations: 1))
            case .reps(_, let count, let steps):
                let isteps = steps.map { st in
                    IntervalStep(st.work ? .work : .recovery, step: WorkoutStep(goal: .time(Double(st.seconds), .seconds)))
                }
                blocks.append(IntervalBlock(steps: isteps, iterations: count))
            }
        }
        guard !blocks.isEmpty else { return nil }
        return CustomWorkout(activity: .running,
                             location: outdoor ? .outdoor : .indoor,
                             displayName: name,
                             warmup: warmup,
                             blocks: blocks,
                             cooldown: cooldown)
    }

    /// Schedules the workout on the paired watch for 7 am on the day.
    static func schedule(name: String, segments: [Segment], on date: Date, outdoor: Bool) async throws {
        guard let workout = customWorkout(name: name, segments: segments, outdoor: outdoor) else { throw ExportError.nothingToSend }
        let state = await WorkoutScheduler.shared.requestAuthorization()
        guard state == .authorized else { throw ExportError.notAuthorized }
        let plan = WorkoutPlan(.custom(workout))
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 7
        comps.minute = 0
        await WorkoutScheduler.shared.schedule(plan, at: comps)
    }
}
#endif

/// Lets the UI ask whether the button should show at all.
enum WatchExportSupport {
    static var isSupported: Bool {
        #if canImport(WorkoutKit)
        return true
        #else
        return false
        #endif
    }
}
