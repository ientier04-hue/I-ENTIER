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

    let phoneChannel = FlutterMethodChannel(
      name: "i_entier/phone",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "phone")!.messenger()
    )
    phoneChannel.setMethodCallHandler { call, result in
      guard call.method == "dial" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let number = arguments["number"] as? String,
        !number.isEmpty,
        let url = URL(string: "tel://\(number)")
      else {
        result(FlutterError(code: "INVALID_NUMBER", message: "Phone number is required.", details: nil))
        return
      }

      guard UIApplication.shared.canOpenURL(url) else {
        result(FlutterError(code: "NO_DIALER", message: "No phone dialer is available.", details: nil))
        return
      }

      UIApplication.shared.open(url) { success in
        if success {
          result(nil)
        } else {
          result(FlutterError(code: "OPEN_FAILED", message: "Could not open the phone dialer.", details: nil))
        }
      }
    }
  }
}
