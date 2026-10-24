import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LifeTwinProtectedStore") {
      let channel = FlutterMethodChannel(name: "lifetwin/protected_store", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(ProtectedStore.handle)
    }
  }
}

/// The LifeTwin store (lib/twin/twin_store.dart): one JSON file in Application Support,
/// written with NSFileProtectionComplete (unreadable while the phone is locked) and
/// excluded from iCloud and computer backups. Nothing is synced or sent.
enum ProtectedStore {
  static func directory() throws -> URL {
    var dir = try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("LifeTwin", isDirectory: true)
    try FileManager.default.createDirectory(
      at: dir, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try dir.setResourceValues(values)
    return dir
  }

  static func file() throws -> URL { try directory().appendingPathComponent("twin_store.json") }

  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    do {
      let url = try file()
      switch call.method {
      case "read":
        result(FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : nil)
      case "write":
        guard let text = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "write needs a string", details: nil))
          return
        }
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        result(nil)
      case "delete":
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        result(nil)
      case "protection":
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        result((attributes[.protectionKey] as? FileProtectionType)?.rawValue)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "store_failed", message: error.localizedDescription, details: nil))
    }
  }
}
