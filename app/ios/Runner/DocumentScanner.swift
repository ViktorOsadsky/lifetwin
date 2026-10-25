import Flutter
import PDFKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import Vision
import VisionKit

/// Scans or picks a health document and recognises its text on the phone with Vision.
///
/// Only text goes back to Dart. Image and PDF bytes stay in memory in this class and are
/// dropped as soon as recognition returns; nothing is written to disk. PDFs are read in
/// place from Files, not copied. The one exception is "pick_pdf": the PDF's bytes go to
/// Dart, in memory, so the person can choose to send it to be read or read it here.
/// See docs/document-upload.md.
final class DocumentScanner: NSObject {
  static let maxPages = 10
  static let maxBytes = 20 * 1024 * 1024
  static let maxChars = 12000

  private var pending: FlutterResult?
  /// "pick_pdf": return the picked PDF's bytes instead of its text.
  private var wantsPdfBytes = false

  static func register(with messenger: FlutterBinaryMessenger) -> DocumentScanner {
    let scanner = DocumentScanner()
    let channel = FlutterMethodChannel(name: "lifetwin/documents", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak scanner] call, result in
      scanner?.handle(call, result: result)
    }
    return scanner
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "scan":
      guard pending == nil else { return result(Self.error("busy")) }
      guard let presenter = Self.topViewController() else { return result(Self.error("failed")) }
      pending = result
      switch args["source"] as? String {
      case "camera": presentCamera(on: presenter)
      case "photos": presentPhotos(on: presenter)
      case "pdf": presentPdf(on: presenter)
      default: finish(.failure("unsupported_type"))
      }
    case "pick_pdf":
      // The PDF's bytes, unread, for the "send it to be read?" question. Held in memory only.
      guard pending == nil else { return result(Self.error("busy")) }
      guard let presenter = Self.topViewController() else { return result(Self.error("failed")) }
      pending = result
      wantsPdfBytes = true
      presentPdf(on: presenter)
    case "recognize":
      // Tests pass a synthetic document; the real flow uses "scan".
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
        return result(Self.error("unsupported_type"))
      }
      let data = bytes.data
      let isPdf = args["type"] as? String == "pdf"
      DispatchQueue.global(qos: .userInitiated).async {
        let outcome: Outcome
        if data.count > Self.maxBytes {
          outcome = .failure("too_large")
        } else if isPdf {
          outcome = PDFDocument(data: data).map(Self.read(pdf:)) ?? .failure("unsupported_type")
        } else {
          outcome = UIImage(data: data).map { Self.read(images: [$0]) } ?? .failure("unsupported_type")
        }
        DispatchQueue.main.async { result(outcome.flutterValue) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Outcome

  enum Outcome {
    case text(pages: [String], pageCount: Int, truncated: Bool)
    case pdf(data: Data, pageCount: Int)
    case failure(String)

    var flutterValue: Any {
      switch self {
      case let .text(pages, pageCount, truncated):
        return ["pages": pages, "page_count": pageCount, "truncated": truncated]
      case let .pdf(data, pageCount):
        return ["bytes": FlutterStandardTypedData(bytes: data), "page_count": pageCount]
      case let .failure(code):
        return DocumentScanner.error(code)
      }
    }
  }

  static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }

  private func finish(_ outcome: Outcome) {
    let result = pending
    pending = nil
    wantsPdfBytes = false
    result?(outcome.flutterValue)
  }

  /// Recognises off the main thread, then reports on it.
  private func finishInBackground(_ work: @escaping () -> Outcome) {
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome = work()
      DispatchQueue.main.async { self.finish(outcome) }
    }
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Sources

  private func presentCamera(on presenter: UIViewController) {
    // The document camera finds the page edges and captures by itself; not on the simulator.
    guard VNDocumentCameraViewController.isSupported else { return finish(.failure("camera_unavailable")) }
    let camera = VNDocumentCameraViewController()
    camera.delegate = self
    presenter.present(camera, animated: true)
  }

  private func presentPhotos(on presenter: UIViewController) {
    // No photo-library permission is needed: the picker runs outside the app.
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = Self.maxPages
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  private func presentPdf(on presenter: UIViewController) {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  // MARK: - Recognition

  static func read(images: [UIImage]) -> Outcome {
    let pages = images.prefix(maxPages).map(recognize(image:))
    return .text(pages: pages, pageCount: images.count, truncated: images.count > maxPages)
  }

  static func read(pdf: PDFDocument) -> Outcome {
    if pdf.isLocked { return .failure("password_protected") }
    var pages: [String] = []
    for index in 0..<min(pdf.pageCount, maxPages) {
      guard let page = pdf.page(at: index) else { continue }
      // Portal downloads usually carry a text layer; use it rather than re-reading pixels.
      let layer = page.string ?? ""
      if layer.filter(\.isLetter).count >= 40 {
        pages.append(String(layer.prefix(maxChars)))
        continue
      }
      let box = page.bounds(for: .mediaBox).size
      let image = page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox)
      pages.append(recognize(image: image))
    }
    return .text(pages: pages, pageCount: pdf.pageCount, truncated: pdf.pageCount > maxPages)
  }

  /// Recognised lines in reading order. Pieces on the same row (a table) are joined with
  /// three spaces, so a label and its value stay on one line.
  static func recognize(image: UIImage) -> String {
    guard let cgImage = image.cgImage else { return "" }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image))
    do { try handler.perform([request]) } catch { return "" }
    let pieces = (request.results ?? []).compactMap { observation -> (CGRect, String)? in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      return (observation.boundingBox, text)
    }
    // Vision's boxes are normalised with the origin at the bottom left.
    let sorted = pieces.sorted { $0.0.midY > $1.0.midY }
    var rows: [[(CGRect, String)]] = []
    for piece in sorted {
      if let last = rows.last?.first, abs(last.0.midY - piece.0.midY) < min(last.0.height, piece.0.height) / 2 {
        rows[rows.count - 1].append(piece)
      } else {
        rows.append([piece])
      }
    }
    let text = rows
      .map { $0.sorted { $0.0.minX < $1.0.minX }.map(\.1).joined(separator: "   ") }
      .joined(separator: "\n")
    return String(text.prefix(maxChars))
  }

  private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
    switch image.imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

// MARK: - Document camera

extension DocumentScanner: VNDocumentCameraViewControllerDelegate {
  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    let images = (0..<scan.pageCount).map(scan.imageOfPage(at:))
    controller.dismiss(animated: true)
    finishInBackground { Self.read(images: images) }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    finish(.failure("cancelled"))
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true)
    finish(.failure("failed"))
  }
}

// MARK: - Photos

extension DocumentScanner: PHPickerViewControllerDelegate {
  private static let photoTypes: [UTType] = [.jpeg, .png, .heic, .heif]

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    if results.isEmpty { return finish(.failure("cancelled")) }
    var images = [UIImage?](repeating: nil, count: results.count)
    var failure: String?
    let group = DispatchGroup()
    for (index, result) in results.enumerated() {
      let provider = result.itemProvider
      guard let type = Self.photoTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
        failure = "unsupported_type"
        continue
      }
      group.enter()
      // Loaded into memory; the picker gives no file the app has to clean up.
      provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
        DispatchQueue.main.async {
          if let data, data.count <= Self.maxBytes, let image = UIImage(data: data) {
            images[index] = image
          } else {
            failure = data.map { $0.count > Self.maxBytes ? "too_large" : "unsupported_type" } ?? "failed"
          }
          group.leave()
        }
      }
    }
    group.notify(queue: .main) {
      if let failure { return self.finish(.failure(failure)) }
      let loaded = images.compactMap { $0 }
      self.finishInBackground { Self.read(images: loaded) }
    }
  }
}

// MARK: - Files (PDF)

extension DocumentScanner: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { return finish(.failure("cancelled")) }
    let wantsBytes = wantsPdfBytes
    finishInBackground {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      if size > Self.maxBytes { return .failure("too_large") }
      if wantsBytes {
        // In memory only; Dart decides, with the person, whether it is sent or read here.
        guard let data = try? Data(contentsOf: url), let pdf = PDFDocument(data: data) else {
          return .failure("unsupported_type")
        }
        if pdf.isLocked { return .failure("password_protected") }
        return .pdf(data: data, pageCount: pdf.pageCount)
      }
      guard let pdf = PDFDocument(url: url) else { return .failure("unsupported_type") }
      return Self.read(pdf: pdf)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(.failure("cancelled"))
  }
}
