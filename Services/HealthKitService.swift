import Foundation
import HealthKit
import SwiftData

struct ImportedRun {
    var uuid: String
    var start: Date
    var minutes: Int
    var km: Double
    var avgHR: Int?
}

/// Reads running workouts from Apple Health (your watch, phone or any app that writes workouts, Strava included if it writes to Health).
/// Read-only: the app never writes to Health.
@MainActor
final class HealthKitService: ObservableObject {
    private let store = HKHealthStore()
    @Published var status: String = ""

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async -> Bool {
        guard Self.available else { status = "Apple Health is not available on this device."; return false }
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning)
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            status = "Health access was not granted."
            return false
        }
    }

    func recentRuns(since: Date) async -> [ImportedRun] {
        let datePredicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        let runPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runPredicate])
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor<HKWorkout>(\.endDate, order: .reverse)],
            limit: 100)
        guard let workouts = try? await descriptor.result(for: store) else { return [] }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        return workouts.map { w in
            let km = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: HKUnit.meterUnit(with: .kilo)) ?? 0
            let hr = w.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?.doubleValue(for: bpm)
            return ImportedRun(uuid: w.uuid.uuidString,
                               start: w.startDate,
                               minutes: Int((w.duration / 60).rounded()),
                               km: km,
                               avgHR: hr.map { Int($0.rounded()) })
        }
    }

    /// Fill in planned sessions from workouts. Same day, still unlogged, not strength: the first one gets the run.
    /// A run with no matching session becomes an extra easy run that still needs a rating.
    /// Returns how many runs were brought in.
    func importRuns(profile: RunnerProfile, sessions: [PlanSession], context: ModelContext) async -> Int {
        guard await requestAccess() else { return 0 }
        let since = max(profile.planStart, Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? profile.planStart)
        let runs = await recentRuns(since: since)
        var brought = 0
        let cal = Calendar.current

        for run in runs {
            if sessions.contains(where: { $0.healthKitUUID == run.uuid }) { continue }
            let sameDay = sessions.filter {
                cal.isDate($0.date, inSameDayAs: run.start) && $0.status == .planned && $0.kind != .strength && $0.healthKitUUID == nil
            }
            if let target = sameDay.first {
                target.status = .done
                target.actualMinutes = run.minutes
                target.actualKm = run.km
                target.avgHR = run.avgHR
                target.healthKitUUID = run.uuid
            } else {
                let monday = PlanGenerator.mondayOf(run.start)
                let sameWeek = sessions.first { PlanGenerator.mondayOf($0.date) == monday }
                let week = sameWeek?.week ?? (profile.weekOffset + 1)
                let extra = PlanSession(week: week, day: PlanGenerator.dayIndex(run.start), date: run.start,
                                        kind: .easy, minutes: run.minutes, progress: 0, isExtra: true)
                extra.status = .done
                extra.actualMinutes = run.minutes
                extra.actualKm = run.km
                extra.avgHR = run.avgHR
                extra.healthKitUUID = run.uuid
                context.insert(extra)
            }
            brought += 1
        }
        return brought
    }
}
