import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceIdentityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerDeviceIdentityChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerDeviceIdentityChannel(messenger: FlutterBinaryMessenger) {
    deviceIdentityChannel = FlutterMethodChannel(
      name: "ccs/device_identity",
      binaryMessenger: messenger
    )

    deviceIdentityChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceId":
        guard let vendorId = UIDevice.current.identifierForVendor?.uuidString.lowercased(),
              !vendorId.isEmpty else {
          result(nil)
          return
        }

        result("ios:\(vendorId)")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
