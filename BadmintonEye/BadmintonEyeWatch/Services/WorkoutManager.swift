import Foundation
import HealthKit

/// Manages HKWorkoutSession lifecycle for badminton matches on Apple Watch.
/// Starts workout when match begins, ends workout when match completes.
/// HealthKit authorization requested at app launch (never mid-match).
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate, @unchecked Sendable {
    static let shared = WorkoutManager()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var isWorkoutActive: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Authorization (call at app launch, NOT mid-match)

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Workout Lifecycle

    func startWorkout() async throws {
        guard !isWorkoutActive else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .badminton
        config.locationType = .indoor

        session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        builder = session?.associatedWorkoutBuilder()

        session?.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: config
        )

        let startDate = Date()
        session?.startActivity(with: startDate)
        try await builder?.beginCollection(at: startDate)
        isWorkoutActive = true
    }

    func endWorkout() async {
        guard isWorkoutActive else { return }

        session?.end()
        let endDate = Date()
        do {
            try await builder?.endCollection(at: endDate)
            try await builder?.finishWorkout()
            // finishWorkout() automatically credits Activity Rings
        } catch {
            // Log but don't crash -- match data is more important than workout data
        }
        isWorkoutActive = false
        session = nil
        builder = nil
    }

    // MARK: - HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        // State tracking handled by isWorkoutActive flag
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        isWorkoutActive = false
    }

    // MARK: - HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No custom event handling needed
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        // Heart rate and energy data collected automatically by HKLiveWorkoutDataSource
    }
}
