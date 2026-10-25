import HealthKit
import XCTest
@testable import Runner

final class HealthActivityTests: XCTestCase {
  private let end = Date(timeIntervalSince1970: 1_792_867_200)

  private func workout(mets: Double? = 4, daysAgo: Int = 1, minutes: Double = 60,
                       metadata: [String: Any]? = nil, events: [HKWorkoutEvent]? = nil) -> HKWorkout {
    let start = end.addingTimeInterval(-Double(daysAgo) * 86400)
    let data = metadata ?? mets.map { [HKMetadataKeyAverageMETs: HKQuantity(unit: HealthActivityBridge.metsUnit, doubleValue: $0)] }
    return HKWorkout(activityType: .other, start: start, end: start.addingTimeInterval(minutes * 60),
                     workoutEvents: events, totalEnergyBurned: nil, totalDistance: nil, metadata: data)
  }

  private func exclusions(_ result: [String: Any]) -> [String: Int] {
    result["excluded_counts"] as! [String: Int]
  }

  func testNativeMETQuantityProducesSeparateFourWeekWholeWorkoutEstimates() {
    let result = HealthActivityBridge.aggregate([
      workout(mets: 3, daysAgo: 1, minutes: 40),
      workout(mets: 5.99, daysAgo: 2, minutes: 20),
      workout(mets: 6, daysAgo: 3, minutes: 80),
      workout(mets: 2.99, daysAgo: 4),
    ], endingAt: end)
    XCTAssertEqual(result["moderate_weekly_minutes"] as? Double, 15)
    XCTAssertEqual(result["vigorous_weekly_minutes"] as? Double, 20)
    XCTAssertEqual(result["eligible_workout_count"] as? Int, 3)
    XCTAssertEqual(exclusions(result)["light_intensity"], 1)
    XCTAssertEqual(result["requires_recreation_confirmation"] as? Bool, true)
    XCTAssertEqual(result["method"] as? String, "whole_workout_mean_mets")
  }

  func testModerateOnlyAndNoDataNeverSupplyVigorousZero() {
    let moderate = HealthActivityBridge.aggregate([workout()], endingAt: end)
    XCTAssertEqual(moderate["moderate_weekly_minutes"] as? Double, 15)
    XCTAssertTrue(moderate["vigorous_weekly_minutes"] is NSNull)
    let empty = HealthActivityBridge.aggregate([], endingAt: end)
    XCTAssertTrue(empty["moderate_weekly_minutes"] is NSNull)
    XCTAssertTrue(empty["vigorous_weekly_minutes"] is NSNull)
    XCTAssertEqual(empty["eligible_workout_count"] as? Int, 0)
  }

  func testRecordedPauseDurationIsUsedWithoutSubtractingPausesTwice() throws {
    let start = end.addingTimeInterval(-86400)
    func event(_ type: HKWorkoutEventType, minute: Double) -> HKWorkoutEvent {
      HKWorkoutEvent(type: type, dateInterval: DateInterval(start: start.addingTimeInterval(minute * 60), duration: 0), metadata: nil)
    }
    let paused = workout(events: [event(.pause, minute: 10), event(.pause, minute: 20),
                                  event(.resume, minute: 30), event(.resume, minute: 40)])
    XCTAssertEqual(try XCTUnwrap(HealthActivityBridge.activeDuration(paused)), 40 * 60, accuracy: 0.001)
    let result = HealthActivityBridge.aggregate([paused], endingAt: end)
    XCTAssertEqual(result["moderate_weekly_minutes"] as? Double, 10)
  }

  func testMissingWrongTypeAndWrongUnitsDoNotFallBackToWorkoutName() {
    let result = HealthActivityBridge.aggregate([
      workout(mets: nil, daysAgo: 1),
      workout(mets: nil, daysAgo: 2),
    ], endingAt: end)
    XCTAssertEqual(exclusions(result)["missing_metadata"], 2)
    XCTAssertTrue(result["moderate_weekly_minutes"] is NSNull)
    XCTAssertTrue(result["vigorous_weekly_minutes"] is NSNull)
    // HealthKit rejects an invalid metadata type during HKWorkout creation.
    // Exercise our defensive conversion boundary without creating such objects.
    XCTAssertNil(HealthActivityBridge.meanMETs("8"))
    XCTAssertNil(HealthActivityBridge.meanMETs(HKQuantity(unit: .minute(), doubleValue: 8)))
  }

  func testDuplicateUUIDIsCountedOnceAndUnresolvedOverlapGroupIsExcluded() {
    let single = workout(daysAgo: 2)
    let start = end.addingTimeInterval(-86400)
    func overlapping(_ offset: TimeInterval) -> HKWorkout {
      HKWorkout(activityType: .running, start: start.addingTimeInterval(offset),
                end: start.addingTimeInterval(offset + 3600), workoutEvents: nil,
                totalEnergyBurned: nil, totalDistance: nil,
                metadata: [HKMetadataKeyAverageMETs: HKQuantity(unit: HealthActivityBridge.metsUnit, doubleValue: 8)])
    }
    let result = HealthActivityBridge.aggregate([single, single, overlapping(0), overlapping(3000), overlapping(6000)], endingAt: end)
    XCTAssertEqual(exclusions(result)["duplicate"], 1)
    XCTAssertEqual(exclusions(result)["overlap"], 3)
    XCTAssertEqual(result["moderate_weekly_minutes"] as? Double, 15)
    XCTAssertTrue(result["vigorous_weekly_minutes"] is NSNull)
  }

  func testBoundaryWorkoutsAreExcludedRatherThanProratingAverageMETs() {
    let result = HealthActivityBridge.aggregate([workout(daysAgo: 29), workout(daysAgo: 0), workout(daysAgo: 28)], endingAt: end)
    XCTAssertEqual(exclusions(result)["boundary"], 2)
    XCTAssertEqual(result["moderate_weekly_minutes"] as? Double, 15)
  }

  func testBoundedQueryOverflowSuppressesEveryEstimateAndResponseContainsOnlyAggregates() {
    let result = HealthActivityBridge.aggregate(Array(repeating: workout(), count: HealthActivityBridge.maxWorkouts + 1), endingAt: end)
    XCTAssertEqual(result["truncated"] as? Bool, true)
    XCTAssertTrue(result["moderate_weekly_minutes"] is NSNull)
    XCTAssertTrue(result["vigorous_weekly_minutes"] is NSNull)
    XCTAssertEqual(Set(result.keys), ["schema", "window_days", "method", "moderate_weekly_minutes",
                                    "vigorous_weekly_minutes", "eligible_workout_count", "excluded_counts",
                                    "truncated", "requires_recreation_confirmation"])
    XCTAssertEqual(result["eligible_workout_count"] as? Int, 0)
  }
}
