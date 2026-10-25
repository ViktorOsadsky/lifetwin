import Flutter
import UIKit
import UniformTypeIdentifiers

/// Bounded, on-phone Files/Open-in delivery. No networking, identifiers in errors,
/// or retained files after an app Inbox copy has been consumed.
final class BandFileBridge: NSObject, UIDocumentPickerDelegate, FlutterStreamHandler {
  static let shared = BandFileBridge()
  static let maxBytes = 5 * 1024 * 1024
  private var pickerResult: FlutterResult?
  private var sink: FlutterEventSink?
  private var queued = [Data]()
  private var queuedBytes = 0
  private var queuedError: String?
  private var generation = 0
  private let intakeQueue = DispatchQueue(label: "com.lifetwin.band-files", qos: .userInitiated)
  // Claimed on the main thread before work is enqueued, and released only after
  // its result returns there. Scene delivery and startup recovery share ownership.
  private var claimedInboxURLs = Set<URL>()
  private let inboxDirectory: URL

  init(inboxDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Inbox", isDirectory: true)) {
    self.inboxDirectory = inboxDirectory.standardizedFileURL
    super.init()
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = shared
    let channel = FlutterMethodChannel(name: "lifetwin/band_files", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in bridge.handle(call, result) }
    FlutterEventChannel(name: "lifetwin/band_file_events", binaryMessenger: messenger).setStreamHandler(bridge)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "available": result(true)
    case "pick":
      guard pickerResult == nil, let presenter = Self.presenter() else {
        return result(Self.error("unavailable"))
      }
      pickerResult = result
      let types = [UTType.json, UTType(importedAs: "com.lifetwin.band-day")]
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
      picker.allowsMultipleSelection = true
      picker.delegate = self
      presenter.present(picker, animated: true)
    case "recoverInbox":
      recoverInbox(result: result)
    case "clear":
      clear(result: result)
    default: result(FlutterMethodNotImplemented)
    }
  }

  static func accepts(_ url: URL) -> Bool {
    url.isFileURL && ["json", "lifetwinband"].contains(url.pathExtension.lowercased())
  }

  /// SceneDelegate calls this for both cold and warm Open-in delivery.
  func receive(_ url: URL) {
    guard Self.accepts(url) else { return }
    let files = claim([url])
    guard !files.isEmpty else { return }
    let request = generation
    intakeQueue.async {
      do {
        let data = try Self.read(url)
        self.removeInboxCopies(files)
        DispatchQueue.main.async {
          guard request == self.generation else { return }
          self.release(files)
          if let sink = self.sink { sink(FlutterStandardTypedData(bytes: data)) }
          else if self.queued.count < 14 && self.queuedBytes + data.count <= Self.maxBytes {
            self.queued.append(data); self.queuedBytes += data.count
          } else { self.queuedError = "too_large" }
        }
      } catch {
        DispatchQueue.main.async {
          guard request == self.generation else { return }
          self.release(files)
          if let sink = self.sink { sink(Self.error("unavailable")) } else { self.queuedError = "unavailable" }
        }
      }
    }
  }

  func recoverInbox(result: @escaping FlutterResult) {
    let urls = (try? FileManager.default.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)) ?? []
    readBatch(urls.filter(Self.accepts).sorted { $0.lastPathComponent < $1.lastPathComponent }, result: result)
  }

  func clear(result: @escaping FlutterResult) {
    generation += 1
    claimedInboxURLs.removeAll()
    queued.removeAll(); queuedBytes = 0; queuedError = nil
    let files = (try? FileManager.default.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: nil)) ?? []
    // Order deletion after outstanding reads, without allowing their stale
    // completions to repopulate the Dart session or the native event queue.
    intakeQueue.async {
      self.removeInboxCopies(files.filter(Self.accepts))
      DispatchQueue.main.async { result(nil) }
    }
  }

  private func isInboxCopy(_ url: URL) -> Bool {
    url.deletingLastPathComponent().standardizedFileURL == inboxDirectory
  }

  private func claim(_ urls: [URL]) -> [URL] {
    var files = [URL]()
    for url in urls {
      let key = url.standardizedFileURL
      if isInboxCopy(url) {
        // A late SceneDelegate callback can refer to a copy recovery already
        // consumed. A fresh delivery at the same path remains eligible.
        if claimedInboxURLs.contains(key) || !FileManager.default.fileExists(atPath: url.path) { continue }
        claimedInboxURLs.insert(key)
      }
      files.append(url)
    }
    return files
  }

  private func release(_ urls: [URL]) {
    for url in urls where isInboxCopy(url) { claimedInboxURLs.remove(url.standardizedFileURL) }
  }

  private func removeInboxCopies(_ urls: [URL]) {
    for url in urls where isInboxCopy(url) { try? FileManager.default.removeItem(at: url) }
  }

  private func readBatch(_ urls: [URL], result: @escaping FlutterResult) {
    guard urls.count <= 14 else { return result(Self.error("too_large")) }
    let files = claim(urls)
    let request = generation
    intakeQueue.async {
      do {
        var total = 0
        var data = [Data]()
        for url in files {
          let bytes = try Self.read(url)
          total += bytes.count
          guard total <= Self.maxBytes else { throw ReadFailure.tooLarge }
          data.append(bytes)
        }
        // Keep every copy on transport failure: Dart receives the whole batch
        // or none of it, so earlier successful reads must remain retryable.
        self.removeInboxCopies(files)
        DispatchQueue.main.async {
          guard request == self.generation else { return result(Self.error("cancelled")) }
          self.release(files)
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      } catch let failure as ReadFailure {
        DispatchQueue.main.async {
          guard request == self.generation else { return result(Self.error("cancelled")) }
          self.release(files)
          result(Self.error(failure == .tooLarge ? "too_large" : "unavailable"))
        }
      } catch {
        DispatchQueue.main.async {
          guard request == self.generation else { return result(Self.error("cancelled")) }
          self.release(files)
          result(Self.error("unavailable"))
        }
      }
    }
  }

  private enum ReadFailure: Error { case tooLarge, unavailable }

  private static func read(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access { url.stopAccessingSecurityScopedResource() }
    }
    var coordinationError: NSError?
    var readError: Error?
    var output: Data?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
      guard let stream = InputStream(url: location) else { readError = ReadFailure.unavailable; return }
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 8192)
      var data = Data()
      while true {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count < 0 { readError = ReadFailure.unavailable; return }
        if count == 0 { output = data; return }
        if data.count + count > maxBytes { readError = ReadFailure.tooLarge; return }
        data.append(contentsOf: bytes.prefix(count))
      }
    }
    if let readError { throw readError }
    guard coordinationError == nil, let output else { throw ReadFailure.unavailable }
    return output
  }

  private static func presenter() -> UIViewController? {
    var controller = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let next = controller?.presentedViewController { controller = next }
    return controller
  }
  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "The band file could not be opened.", details: nil)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pickerResult else { return }
    pickerResult = nil
    readBatch(urls, result: result)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pickerResult?(Self.error("cancelled")); pickerResult = nil
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    let pending = queued; queued.removeAll(); queuedBytes = 0
    for data in pending { events(FlutterStandardTypedData(bytes: data)) }
    if let code = queuedError { queuedError = nil; events(Self.error(code)) }
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }
}
