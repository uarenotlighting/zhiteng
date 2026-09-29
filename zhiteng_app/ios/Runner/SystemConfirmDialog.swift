import Flutter
import UIKit

enum SystemConfirmDialog {
  private static let channelName = "zhiteng/system_dialog"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "confirm" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.main.async {
        present(args: args, result: result)
      }
    }
  }

  private static func present(args: [String: Any], result: @escaping FlutterResult) {
    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "no_view",
          message: "找不到可以弹出系统确认框的页面",
          details: nil
        )
      )
      return
    }

    let title = args["title"] as? String ?? ""
    let message = args["message"] as? String ?? ""
    let stay = args["stay"] as? String ?? "取消"
    let discard = args["discard"] as? String ?? "确定"
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: stay, style: .cancel) { _ in
      result(false)
    })
    alert.addAction(UIAlertAction(title: discard, style: .destructive) { _ in
      result(true)
    })
    presenter.present(alert, animated: true)
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}
