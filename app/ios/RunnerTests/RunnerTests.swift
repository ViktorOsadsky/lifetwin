import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
  }

  @MainActor
  func testOpenInBeforeRecoveryConsumesEachInboxCopyOnce() throws {
    let inbox = try temporaryDirectory()
    let first = inbox.appendingPathComponent("a.json")
    let second = inbox.appendingPathComponent("b.json")
    let firstBytes = Data("{\"synthetic_demo\":true,\"test\":1}".utf8)
    let secondBytes = Data("{\"synthetic_demo\":true,\"test\":2}".utf8)
    try firstBytes.write(to: first)
    try secondBytes.write(to: second)
    let bridge = BandFileBridge(inboxDirectory: inbox)
    let event = expectation(description: "Open-in delivery")
    let recovery = expectation(description: "Remaining Inbox delivery")
    var received = [Data]()
    bridge.onListen(withArguments: nil) { value in
      guard let bytes = value as? FlutterStandardTypedData else { return XCTFail("Unexpected delivery failure") }
      received.append(bytes.data)
      event.fulfill()
    }

    bridge.receive(first)
    bridge.recoverInbox { value in
      let files = value as? [FlutterStandardTypedData]
      XCTAssertEqual(files?.map(\.data), [secondBytes])
      recovery.fulfill()
    }
    wait(for: [event, recovery], timeout: 5)
    XCTAssertEqual(received, [firstBytes])
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), [])
  }

  @MainActor
  func testRecoveryBeforeOpenInSkipsDuplicateAndAllowsFreshCopyAtSamePath() throws {
    let inbox = try temporaryDirectory()
    let url = inbox.appendingPathComponent("day.json")
    let bytes = Data("{\"synthetic_demo\":true}".utf8)
    try bytes.write(to: url)
    let bridge = BandFileBridge(inboxDirectory: inbox)
    let recovered = expectation(description: "Recovery owns the copy")
    var received = [Data]()
    bridge.onListen(withArguments: nil) { value in
      guard let data = value as? FlutterStandardTypedData else { return XCTFail("Unexpected delivery failure") }
      received.append(data.data)
    }
    bridge.recoverInbox { value in
      XCTAssertEqual((value as? [FlutterStandardTypedData])?.map(\.data), [bytes])
      recovered.fulfill()
    }
    bridge.receive(url)
    wait(for: [recovered], timeout: 5)
    bridge.receive(url) // A delayed callback for the now-consumed copy.
    XCTAssertTrue(received.isEmpty)

    try bytes.write(to: url)
    let fresh = expectation(description: "Fresh copy at reused path")
    bridge.onListen(withArguments: nil) { value in
      XCTAssertEqual((value as? FlutterStandardTypedData)?.data, bytes)
      fresh.fulfill()
    }
    bridge.receive(url)
    wait(for: [fresh], timeout: 5)
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  @MainActor
  func testFailedBatchRetainsEarlierReadsForRetryAndPreservesOriginals() throws {
    let inbox = try temporaryDirectory()
    let good = inbox.appendingPathComponent("a-good.json")
    let tooLarge = inbox.appendingPathComponent("z-large.json")
    let bytes = Data("{\"synthetic_demo\":true}".utf8)
    try bytes.write(to: good)
    try Data(repeating: 0, count: BandFileBridge.maxBytes + 1).write(to: tooLarge)
    let bridge = BandFileBridge(inboxDirectory: inbox)
    let failed = expectation(description: "Batch transport failure")
    bridge.recoverInbox { value in
      XCTAssertEqual((value as? FlutterError)?.code, "too_large")
      failed.fulfill()
    }
    wait(for: [failed], timeout: 5)
    XCTAssertTrue(FileManager.default.fileExists(atPath: good.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: tooLarge.path))

    try FileManager.default.removeItem(at: tooLarge)
    let retried = expectation(description: "Retry retains previously read report")
    bridge.recoverInbox { value in
      XCTAssertEqual((value as? [FlutterStandardTypedData])?.map(\.data), [bytes])
      retried.fulfill()
    }
    wait(for: [retried], timeout: 5)
    XCTAssertFalse(FileManager.default.fileExists(atPath: good.path))

    let originals = try temporaryDirectory()
    let original = originals.appendingPathComponent("original.json")
    try bytes.write(to: original)
    let delivered = expectation(description: "External original delivered")
    bridge.onListen(withArguments: nil) { value in
      XCTAssertEqual((value as? FlutterStandardTypedData)?.data, bytes)
      delivered.fulfill()
    }
    bridge.receive(original)
    wait(for: [delivered], timeout: 5)
    XCTAssertEqual(try Data(contentsOf: original), bytes)
  }

  @MainActor
  func testClearCancelsOutstandingRecoveryAndDiscardsQueuedOpenIn() throws {
    let inbox = try temporaryDirectory()
    let url = inbox.appendingPathComponent("day.json")
    let other = inbox.appendingPathComponent("other.json")
    try Data("{\"synthetic_demo\":true}".utf8).write(to: url)
    try Data("{\"synthetic_demo\":true}".utf8).write(to: other)
    let bridge = BandFileBridge(inboxDirectory: inbox)
    let recovery = expectation(description: "Outstanding recovery cancelled")
    let cleared = expectation(description: "Clear completed")
    bridge.receive(url)
    bridge.recoverInbox { value in
      XCTAssertEqual((value as? FlutterError)?.code, "cancelled")
      recovery.fulfill()
    }
    bridge.clear { _ in cleared.fulfill() }
    wait(for: [recovery, cleared], timeout: 5)
    var events = 0
    bridge.onListen(withArguments: nil) { _ in events += 1 }
    XCTAssertEqual(events, 0)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: inbox.path), [])
  }

}
