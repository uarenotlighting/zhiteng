import Flutter
import UIKit

enum SystemDateTimePicker {
  static let channelName = "zhiteng/system_datetime"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "pick" else {
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
          message: "找不到可以弹出系统日期选择器的页面",
          details: nil
        )
      )
      return
    }
    let controller = SystemDateTimeController(
      initial: date(from: args["initial"]) ?? Date(),
      minimum: date(from: args["minimum"]),
      maximum: date(from: args["maximum"])
    ) { picked in
      if let picked {
        result(Int(picked.timeIntervalSince1970 * 1000))
      } else {
        result(nil)
      }
    }
    let navigation = UINavigationController(rootViewController: controller)
    navigation.modalPresentationStyle = .pageSheet
    if #available(iOS 15.0, *) {
      if let sheet = navigation.sheetPresentationController {
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = true
      }
    }
    presenter.present(navigation, animated: true)
  }

  private static func date(from value: Any?) -> Date? {
    guard let number = value as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: number.doubleValue / 1000)
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

private final class SystemDateTimeController: UIViewController {
  private let picker = UIDatePicker()
  private let onFinish: (Date?) -> Void
  private var finished = false

  init(initial: Date, minimum: Date?, maximum: Date?, onFinish: @escaping (Date?) -> Void) {
    self.onFinish = onFinish
    super.init(nibName: nil, bundle: nil)
    let locale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    picker.locale = locale
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    picker.calendar = calendar
    picker.datePickerMode = .dateAndTime
    if #available(iOS 14.0, *) {
      picker.preferredDatePickerStyle = .inline
    }
    picker.locale = locale
    if let minimum {
      picker.minimumDate = minimum
    }
    if let maximum {
      picker.maximumDate = maximum
    }
    let lower = picker.minimumDate ?? .distantPast
    let upper = picker.maximumDate ?? .distantFuture
    picker.date = min(max(initial, lower), upper)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(cancel)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .done,
      target: self,
      action: #selector(done)
    )
    picker.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(picker)
    NSLayoutConstraint.activate([
      picker.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      picker.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
    ])
  }

  @objc private func cancel() {
    finish(nil)
  }

  @objc private func done() {
    finish(picker.date)
  }

  private func finish(_ date: Date?) {
    guard !finished else { return }
    finished = true
    dismiss(animated: true) {
      self.onFinish(date)
    }
  }
}
