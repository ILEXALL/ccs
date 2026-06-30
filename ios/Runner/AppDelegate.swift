import Flutter
import PhotosUI
import UserNotifications
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var photoPickerChannel: FlutterMethodChannel?
  private var deviceIdentityChannel: FlutterMethodChannel?
  private var appBadgeChannel: FlutterMethodChannel?
  private var pendingPhotoResult: FlutterResult?
  private weak var activePhotoPicker: PHPickerViewController?
  private var isCompletingPhotoPick = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPhotoPickerChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerDeviceIdentityChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerAppBadgeChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerPhotoPickerChannel(messenger: FlutterBinaryMessenger) {
    photoPickerChannel = FlutterMethodChannel(
      name: "ccs/photo_picker",
      binaryMessenger: messenger
    )

    photoPickerChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "pickPhoto":
        DispatchQueue.main.async {
          self?.openPhotoPicker(result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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

  private func registerAppBadgeChannel(messenger: FlutterBinaryMessenger) {
    appBadgeChannel = FlutterMethodChannel(
      name: "ccs/app_badge",
      binaryMessenger: messenger
    )

    appBadgeChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadgeCount":
        let arguments = call.arguments as? [String: Any]
        let count = max(0, arguments?["count"] as? Int ?? 0)
        self.setAppIconBadgeCount(count, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setAppIconBadgeCount(_ count: Int, result: @escaping FlutterResult) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(count) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(
              FlutterError(
                code: "badge_update_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
            return
          }

          result(nil)
        }
      }
      return
    }

    UIApplication.shared.applicationIconBadgeNumber = count
    result(nil)
  }

  private func openPhotoPicker(result: @escaping FlutterResult) {
    guard pendingPhotoResult == nil else {
      result(
        FlutterError(
          code: "picker_busy",
          message: "Photo picker is already open.",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "picker_unavailable",
          message: "Could not open photo picker.",
          details: nil
        )
      )
      return
    }

    pendingPhotoResult = result

    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .compatible

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    activePhotoPicker = picker
    isCompletingPhotoPick = false
    picker.presentationController?.delegate = self
    presenter.present(picker, animated: true) { [weak self, weak picker] in
      guard let self = self, let picker = picker else {
        return
      }

      picker.presentationController?.delegate = self
      if picker.presentingViewController == nil {
        self.completePhotoPicker(
          with: FlutterError(
            code: "picker_unavailable",
            message: "Could not open photo picker.",
            details: nil
          )
        )
      }
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard pendingPhotoResult != nil else {
      return
    }

    isCompletingPhotoPick = true

    guard let itemProvider = results.first?.itemProvider else {
      picker.dismiss(animated: true) { [weak self] in
        self?.completePhotoPicker(with: nil)
      }
      return
    }

    guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
      picker.dismiss(animated: true) { [weak self] in
        self?.completePhotoPicker(
          with: FlutterError(
            code: "unsupported_image",
            message: "Could not read the selected photo.",
            details: nil
          )
        )
      }
      return
    }

    picker.dismiss(animated: true) {
      itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
        DispatchQueue.main.async {
          guard let self = self else {
            return
          }

          if let error = error {
            self.completePhotoPicker(
              with: FlutterError(
                code: "photo_load_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
            return
          }

          guard let image = object as? UIImage else {
            self.completePhotoPicker(
              with: FlutterError(
                code: "photo_load_failed",
                message: "Could not read the selected photo.",
                details: nil
              )
            )
            return
          }

          do {
            self.completePhotoPicker(
              with: try self.writePickedImageToTemporaryJpeg(image)
            )
          } catch {
            self.completePhotoPicker(
              with: FlutterError(
                code: "photo_copy_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        }
      }
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === activePhotoPicker,
          !isCompletingPhotoPick else {
      return
    }

    completePhotoPicker(with: nil)
  }

  private func completePhotoPicker(with value: Any?) {
    guard let result = pendingPhotoResult else {
      return
    }

    pendingPhotoResult = nil
    activePhotoPicker?.presentationController?.delegate = nil
    activePhotoPicker = nil
    isCompletingPhotoPick = false
    result(value)
  }
  private func writePickedImageToTemporaryJpeg(_ image: UIImage) throws -> String {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = image.scale
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let normalizedImage = renderer.image { context in
      UIColor.white.setFill()
      context.fill(CGRect(origin: .zero, size: image.size))
      image.draw(in: CGRect(origin: .zero, size: image.size))
    }

    guard let jpegData = normalizedImage.jpegData(compressionQuality: 0.92) else {
      throw NSError(
        domain: "CCSPhotoPicker",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Could not prepare selected photo."]
      )
    }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ccs_photo_picker", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let fileUrl = directory.appendingPathComponent("photo_\(timestamp).jpg")
    try jpegData.write(to: fileUrl, options: .atomic)

    return fileUrl.path
  }

  private func topViewController() -> UIViewController? {
    let rootViewController = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController

    return topViewController(from: rootViewController)
  }

  private func topViewController(from viewController: UIViewController?) -> UIViewController? {
    if let navigationController = viewController as? UINavigationController {
      return topViewController(from: navigationController.visibleViewController)
    }

    if let tabBarController = viewController as? UITabBarController {
      return topViewController(from: tabBarController.selectedViewController)
    }

    if let presentedViewController = viewController?.presentedViewController {
      return topViewController(from: presentedViewController)
    }

    return viewController
  }
}
