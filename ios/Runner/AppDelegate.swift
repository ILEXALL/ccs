import AVFoundation
import AuthenticationServices
import Flutter
import PhotosUI
import UserNotifications
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var feedbackPlayer: AVAudioPlayer?
  private var photoPickerChannel: FlutterMethodChannel?
  private var deviceIdentityChannel: FlutterMethodChannel?
  private var appBadgeChannel: FlutterMethodChannel?
  private var systemNotificationsChannel: FlutterMethodChannel?
  private var pendingPhotoResult: FlutterResult?
  private weak var activePhotoPicker: PHPickerViewController?
  private var isCompletingPhotoPick = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    engineBridge.applicationRegistrar.register(
      CCSAppleSignInButtonFactory(messenger: engineBridge.applicationRegistrar.messenger()),
      withId: "ccs/apple_sign_in_button"
    )
    UNUserNotificationCenter.current().delegate = self
    registerPhotoPickerChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerDeviceIdentityChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerAppBadgeChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerSystemNotificationsChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerPhotoPickerChannel(messenger: FlutterBinaryMessenger) {
    photoPickerChannel = FlutterMethodChannel(
      name: "ccs/photo_picker",
      binaryMessenger: messenger
    )

    photoPickerChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "takePhoto":
        DispatchQueue.main.async {
          self?.openCamera(result: result)
        }
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

  private func registerSystemNotificationsChannel(messenger: FlutterBinaryMessenger) {
    systemNotificationsChannel = FlutterMethodChannel(
      name: "ccs/system_notifications",
      binaryMessenger: messenger
    )

    systemNotificationsChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "stopSound":
        self.feedbackPlayer?.stop()
        self.feedbackPlayer = nil
        result(nil)
      case "playSound":
        let arguments = call.arguments as? [String: Any]
        let name = arguments?["sound"] as? String == "level" ? "level" : "bell"
        if let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
          do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            self.feedbackPlayer = try AVAudioPlayer(contentsOf: url)
            self.feedbackPlayer?.prepareToPlay()
            self.feedbackPlayer?.play()
          } catch { /* Audio must not interrupt the app. */ }
        }
        result(nil)
      case "showNotification":
        let arguments = call.arguments as? [String: Any]
        let id = arguments?["id"] as? Int ?? Int(Date().timeIntervalSince1970)
        let title = arguments?["title"] as? String ?? "CCS"
        let body = arguments?["body"] as? String ?? ""
        let badgeCount = max(1, arguments?["badgeCount"] as? Int ?? 1)
        self.showSystemNotification(
          id: id,
          title: title,
          body: body,
          badgeCount: badgeCount,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func showSystemNotification(
    id: Int,
    title: String,
    body: String,
    badgeCount: Int,
    result: @escaping FlutterResult
  ) {
    let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanBody.isEmpty else {
      result(nil)
      return
    }

    let content = UNMutableNotificationContent()
    content.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "CCS" : title
    content.body = cleanBody
    content.sound = nil // Foreground bell watcher owns sound playback.
    content.badge = NSNumber(value: badgeCount)

    let request = UNNotificationRequest(
      identifier: "ccs-\(id)",
      content: content,
      trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
      DispatchQueue.main.async {
        if let error = error {
          result(
            FlutterError(
              code: "notification_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
          return
        }

        result(nil)
      }
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    super.userNotificationCenter(center, willPresent: notification) { _ in
      // Dart applies the launch cutoff before creating a local foreground alert.
      // Let FCM deliver the message to Dart without presenting the raw push twice.
      if notification.request.trigger is UNPushNotificationTrigger {
        completionHandler([])
        return
      }
      if #available(iOS 14.0, *) {
        completionHandler([.banner, .list, .badge])
      } else {
        completionHandler([.alert, .badge])
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

  private func openCamera(result: @escaping FlutterResult) {
    guard pendingPhotoResult == nil else {
      result(FlutterError(code: "picker_busy", message: "Photo picker is already open.", details: nil))
      return
    }
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      result(FlutterError(code: "camera_unavailable", message: "Camera is not available on this device.", details: nil))
      return
    }
    pendingPhotoResult = result
    AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
      DispatchQueue.main.async {
        guard let self = self else { return }
        guard allowed, let presenter = self.topViewController() else {
          self.completePhotoPicker(with: FlutterError(code: "camera_denied", message: "Allow camera access in Settings to take a photo.", details: nil))
          return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        presenter.present(picker, animated: true)
      }
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true) { self.completePhotoPicker(with: nil) }
  }

  func imagePickerController(_ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    var value: Any?
    do {
      guard let image = info[.originalImage] as? UIImage else {
        throw NSError(domain: "CCSCamera", code: 1)
      }
      value = try writePickedImageToTemporaryJpeg(image)
    } catch {
      value = FlutterError(code: "camera_save_failed", message: "Could not save camera photo.", details: nil)
    }
    picker.dismiss(animated: true) { self.completePhotoPicker(with: value) }
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

private final class CCSAppleSignInButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    CCSAppleSignInButton(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
  }
}

private final class CCSAppleSignInButton: NSObject, FlutterPlatformView {
  private let button = ASAuthorizationAppleIDButton(type: .continue, style: .white)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "ccs/apple_sign_in_button/\(viewId)", binaryMessenger: messenger)
    super.init()
    button.frame = frame
    button.cornerRadius = 16
    button.isEnabled = (arguments as? [String: Any])?["enabled"] as? Bool ?? true
    button.addTarget(self, action: #selector(pressed), for: .touchUpInside)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setEnabled", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.button.isEnabled = enabled
      result(nil)
    }
  }

  @objc private func pressed() {
    guard button.isEnabled else { return }
    channel.invokeMethod("pressed", arguments: nil)
  }

  func view() -> UIView { button }

  deinit { channel.setMethodCallHandler(nil) }
}
