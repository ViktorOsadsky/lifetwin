import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts where BandFileBridge.accepts(context.url) {
      BandFileBridge.shared.receive(context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    let other = contexts.filter { !BandFileBridge.accepts($0.url) }
    if !other.isEmpty { super.scene(scene, openURLContexts: Set(other)) }
    for context in contexts where BandFileBridge.accepts(context.url) {
      BandFileBridge.shared.receive(context.url)
    }
  }
}
