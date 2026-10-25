import Flutter
import HealthKit

/// Read-only, bounded workout estimates. Raw workouts and metadata stay native;
/// only 28-day aggregates cross this on-phone channel. No logging or persistence.
final class HealthActivityBridge {
  static let maxWorkouts = 2000
  static let windowSeconds: TimeInterval = 28 * 24 * 60 * 60
  static let metsUnit = HKUnit(from: "kcal/(kg*hr)")
  private let store = HKHealthStore()
  private var pending: FlutterResult?
  private var query: HKQuery?
  private var timer: DispatchWorkItem?
  private var requestID: UUID?

  static func register(with messenger: FlutterBinaryMessenger) -> HealthActivityBridge {
    let bridge = HealthActivityBridge()
    let channel = FlutterMethodChannel(name: "lifetwin/health_activity", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak bridge] call, result in bridge?.handle(call, result: result) }
    return bridge
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "readWorkoutAverages" else { return result(FlutterMethodNotImplemented) }
    guard pending == nil else { return result(Self.error("busy")) }
    guard HKHealthStore.isHealthDataAvailable() else { return result(Self.error("unavailable")) }
    guard let args = call.arguments as? [String: Any], args.count == 1,
          let milliseconds = args["end_ms"] as? NSNumber,
          CFGetTypeID(milliseconds) != CFBooleanGetTypeID(),
          milliseconds.doubleValue.isFinite,
          milliseconds.doubleValue.rounded() == milliseconds.doubleValue,
          milliseconds.doubleValue > Self.windowSeconds * 1000,
          milliseconds.doubleValue <= Date().addingTimeInterval(60).timeIntervalSince1970 * 1000
    else { return result(Self.error("bad_args")) }
    let end = Date(timeIntervalSince1970: milliseconds.doubleValue / 1000)
    let start = end.addingTimeInterval(-Self.windowSeconds)
    let id = UUID()
    pending = result
    requestID = id
    // Query overlap so boundary-crossing workouts can be excluded explicitly.
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    let read = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                             limit: Self.maxWorkouts + 1,
                             sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) {
      [weak self] _, samples, failure in
      guard let self else { return }
      let value: Any
      if failure != nil {
        value = Self.error("read_failed")
      } else if let workouts = samples as? [HKWorkout] {
        value = Self.aggregate(workouts, endingAt: end)
      } else {
        value = Self.error("read_failed")
      }
      DispatchQueue.main.async { self.finish(value, requestID: id) }
    }
    query = read
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.requestID == id else { return }
      if let query = self.query { self.store.stop(query) }
      self.finish(Self.error("timeout"), requestID: id)
    }
    timer = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    // The existing Health reader requests read-only workout permission. An
    // empty result cannot distinguish no workouts from refused read access.
    store.execute(read)
  }

  private func finish(_ value: Any, requestID id: UUID) {
    guard requestID == id else { return }
    let result = pending
    timer?.cancel()
    timer = nil
    query = nil
    pending = nil
    requestID = nil
    result?(value)
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }

  /// Pure extraction/aggregation seam, exercised with real HKWorkout objects.
  /// This classifies each WHOLE workout by its mean MET, not minutes in zones.
  /// Apple: developer.apple.com/documentation/healthkit/hkmetadatakeyaveragemets
  /// CDC: cdc.gov/physical-activity-basics/measuring/index.html
  static func aggregate(_ workouts: [HKWorkout], endingAt end: Date) -> [String: Any] {
    var excluded = ["missing_metadata": 0, "duration": 0, "overlap": 0,
                    "boundary": 0, "light_intensity": 0, "duplicate": 0]
    func response(moderate: Double = 0, vigorous: Double = 0, eligible: Int = 0,
                  truncated: Bool = false) -> [String: Any] {
      ["schema": "apple_health_workout_averages.v0", "window_days": 28,
       "method": "whole_workout_mean_mets",
       "moderate_weekly_minutes": moderate > 0 ? moderate / 240 : NSNull(),
       "vigorous_weekly_minutes": vigorous > 0 ? vigorous / 240 : NSNull(),
       "eligible_workout_count": eligible, "excluded_counts": excluded,
       "truncated": truncated, "requires_recreation_confirmation": true]
    }
    guard workouts.count <= maxWorkouts else { return response(truncated: true) }
    let start = end.addingTimeInterval(-windowSeconds)
    var seen = Set<UUID>()
    var valid = [(workout: HKWorkout, seconds: Double)]()
    for workout in workouts {
      guard seen.insert(workout.uuid).inserted else { excluded["duplicate"]! += 1; continue }
      guard workout.startDate >= start, workout.endDate <= end else {
        excluded["boundary"]! += 1; continue
      }
      guard let seconds = activeDuration(workout) else { excluded["duration"]! += 1; continue }
      valid.append((workout, seconds))
    }
    valid.sort { $0.workout.startDate < $1.workout.startDate }
    var moderate = 0.0, vigorous = 0.0, eligible = 0
    // Exclude every member of an overlapping connected group, including records
    // without MET metadata. Picking a source would invent a preference/total.
    func consume(_ group: [(workout: HKWorkout, seconds: Double)]) {
      guard group.count == 1, let item = group.first else {
        excluded["overlap"]! += group.count; return
      }
      guard let mets = meanMETs(item.workout.metadata?[HKMetadataKeyAverageMETs]) else {
        excluded["missing_metadata"]! += 1; return
      }
      guard mets >= 3 else { excluded["light_intensity"]! += 1; return }
      eligible += 1
      if mets < 6 { moderate += item.seconds } else { vigorous += item.seconds }
    }
    var group = [(workout: HKWorkout, seconds: Double)]()
    var groupEnd = Date.distantPast
    for item in valid {
      if !group.isEmpty, item.workout.startDate >= groupEnd {
        consume(group); group.removeAll(keepingCapacity: true)
      }
      group.append(item)
      groupEnd = max(groupEnd, item.workout.endDate)
    }
    if !group.isEmpty { consume(group) }
    return response(moderate: moderate, vigorous: vigorous, eligible: eligible)
  }

  static func meanMETs(_ value: Any?) -> Double? {
    guard let quantity = value as? HKQuantity, quantity.is(compatibleWith: metsUnit) else { return nil }
    let mets = quantity.doubleValue(for: metsUnit)
    return mets.isFinite && mets > 0 ? mets : nil
  }

  /// HKWorkout.duration already accounts for pauses: never subtract twice.
  /// Explicit-duration constructors also exist, so reject impossible duration
  /// and disagreement with any available pause/resume event timeline.
  static func activeDuration(_ workout: HKWorkout) -> TimeInterval? {
    let elapsed = workout.endDate.timeIntervalSince(workout.startDate)
    let duration = workout.duration
    guard elapsed.isFinite, duration.isFinite, elapsed > 0, duration > 0,
          duration <= elapsed + 0.001 else { return nil }
    let pauses = (workout.workoutEvents ?? []).filter { $0.type == .pause || $0.type == .resume }
    if !pauses.isEmpty {
      var active = true, cursor = workout.startDate, calculated = 0.0
      for event in pauses {
        let date = event.dateInterval.start
        guard date >= cursor, date <= workout.endDate else { return nil }
        if active { calculated += date.timeIntervalSince(cursor) }
        // Duplicate pause/resume events are ignored, as HealthKit specifies.
        if event.type == .pause { active = false } else { active = true }
        cursor = date
      }
      if active { calculated += workout.endDate.timeIntervalSince(cursor) }
      guard abs(calculated - duration) <= 1 else { return nil }
    }
    return duration
  }
}
