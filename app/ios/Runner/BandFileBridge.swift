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
      let inbox = Self.inbox()
      let urls = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
      let files = urls.filter(Self.accepts)
      readBatch(files, result: result)
    case "clear":
      generation += 1
      queued.removeAll(); queuedBytes = 0; queuedError = nil
      let files = (try? FileManager.default.contentsOfDirectory(at: Self.inbox(), includingPropertiesForKeys: nil)) ?? []
      for url in files where Self.accepts(url) { try? FileManager.default.removeItem(at: url) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  static func accepts(_ url: URL) -> Bool {
    url.isFileURL && ["json", "lifetwinband"].contains(url.pathExtension.lowercased())
  }

  /// SceneDelegate calls this for both cold and warm Open-in delivery.
  func receive(_ url: URL) {
    guard Self.accepts(url) else { return }
    let request = generation
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let data = try Self.read(url)
        DispatchQueue.main.async {
          guard request == self.generation else { return }
          if let sink = self.sink { sink(FlutterStandardTypedData(bytes: data)) }
          else if self.queued.count < 14 && self.queuedBytes + data.count <= Self.maxBytes {
            self.queued.append(data); self.queuedBytes += data.count
          } else { self.queuedError = "too_large" }
        }
      } catch {
        DispatchQueue.main.async {
          guard request == self.generation else { return }
          if let sink = self.sink { sink(Self.error("unavailable")) } else { self.queuedError = "unavailable" }
        }
      }
    }
  }

  private func readBatch(_ urls: [URL], result: @escaping FlutterResult) {
    guard urls.count <= 14 else { return result(Self.error("too_large")) }
    let request = generation
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        var total = 0
        var data = [Data]()
        for url in urls {
          let bytes = try Self.read(url)
          total += bytes.count
          guard total <= Self.maxBytes else { throw ReadFailure.tooLarge }
          data.append(bytes)
        }
        DispatchQueue.main.async {
          guard request == self.generation else { return result(Self.error("cancelled")) }
          result(data.map { FlutterStandardTypedData(bytes: $0) })
        }
      } catch let failure as ReadFailure {
        DispatchQueue.main.async { result(Self.error(failure == .tooLarge ? "too_large" : "unavailable")) }
      } catch {
        DispatchQueue.main.async { result(Self.error("unavailable")) }
      }
    }
  }

  private enum ReadFailure: Error { case tooLarge, unavailable }

  private static func read(_ url: URL) throws -> Data {
    let access = url.startAccessingSecurityScopedResource()
    defer {
      if access { url.stopAccessingSecurityScopedResource() }
      // Delete only OS-delivered app Inbox copies, never the user's original.
      if url.deletingLastPathComponent().standardizedFileURL == inbox().standardizedFileURL {
        try? FileManager.default.removeItem(at: url)
      }
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

  private static func inbox() -> URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Inbox", isDirectory: true)
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
