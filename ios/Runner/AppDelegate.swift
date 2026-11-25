import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// 文件选择通道：与 Android MainActivity.kt 的 FILE_PICKER_CHANNEL 保持一致
  private static let filePickerChannelName = "com.qlapp.qinglong_app/file_picker"

  /// 等待 UIDocumentPickerViewController 回调的 FlutterResult
  private var filePickerResult: FlutterResult?

  /// 本次选择是否为多选（pickFiles），决定回调回传单个 map 还是数组
  private var filePickerMultiple = false

  /// 保存文件的临时源地址（UIDocumentPicker 导出完成后删除）
  private var pendingExportURL: URL?

  /// 上次保存到的目录（Dir 级 bookmark 持久化在 UserDefaults，
  /// 下次打开保存面板直接停在该目录，用户不必每次重新导航）
  private static let lastSaveDirKey = "ql_last_save_directory_bookmark"
  private static let lastSaveDirPathKey = "ql_last_save_directory_path"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let pickerChannel = FlutterMethodChannel(
        name: AppDelegate.filePickerChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      pickerChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(nil)
          return
        }
        if call.method == "pickFile" {
          self.presentFilePicker(from: controller, multiple: false, result: result)
        } else if call.method == "pickFiles" {
          self.presentFilePicker(from: controller, multiple: true, result: result)
        } else if call.method == "saveFile" {
          let args = call.arguments as? [String: Any]
          let fileName = (args?["fileName"] as? String) ?? "qinglong_export.txt"
          let content = (args?["content"] as? String) ?? ""
          let initialDir = (args?["initialDirectory"] as? String) ?? ""
          self.presentSavePicker(
            from: controller,
            fileName: fileName,
            content: content,
            initialDirectory: initialDir,
            result: result
          )
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - 保存文件（用户自选目录）

  /// 弹出系统「存储到…」面板，让用户自己选择保存位置。
  ///
  /// 为什么必须这么做：应用沙盒目录（Documents / tmp）在 iOS「文件」App 里
  /// 默认不可见，用户点下载后去文件管理里找不到任何东西。走 UIDocumentPicker
  /// 导出，文件会被拷到用户指定的 iCloud Drive / 我的 iPhone / 第三方 App
  /// 目录，位置由用户决定且立即可见。
  private func presentSavePicker(
    from controller: UIViewController,
    fileName: String,
    content: String,
    initialDirectory: String,
    result: @escaping FlutterResult
  ) {
    if filePickerResult != nil {
      result(nil)
      return
    }

    // 1. 先把内容写到沙盒临时文件（UIDocumentPicker 导出需要一个真实文件 URL）
    let safeName = AppDelegate.sanitizeFileName(fileName)
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ql_exports", isDirectory: true)
    let srcURL = tempDir.appendingPathComponent(safeName)
    do {
      try FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: srcURL.path) {
        try? FileManager.default.removeItem(at: srcURL)
      }
      guard let data = content.data(using: .utf8) else {
        result(FlutterError(code: "encode", message: "内容编码失败", details: nil))
        return
      }
      try data.write(to: srcURL, options: .atomic)
    } catch {
      result(
        FlutterError(
          code: "io",
          message: "临时文件写入失败：\(error.localizedDescription)",
          details: nil
        )
      )
      return
    }

    filePickerResult = result
    filePickerMultiple = false
    pendingExportURL = srcURL

    // 2. 构造导出面板。
    //    forExporting:asCopy: 是 iOS 14+ 才有的 API（部署目标 13.0，
    //    直接调用会报 "'init(forExporting:asCopy:)' is only available in iOS 14.0"），
    //    iOS 13 回退到旧的 init(url:in:.exportToService)。
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [srcURL], asCopy: true)
      // 默认停在「上次保存的目录」：bookmark 优先（跨重启有效），
      // 失效时用记录下来的路径兜底
      if let dirURL = resolveLastSaveDirectory(hint: initialDirectory) {
        picker.directoryURL = dirURL
      }
    } else {
      picker = UIDocumentPickerViewController(url: srcURL, in: .exportToService)
      _ = initialDirectory  // iOS 13 无 directoryURL，面板自行记住上次位置
    }
    picker.delegate = self
    controller.present(picker, animated: true)
  }

  /// 解析上次保存目录：bookmark → 路径 → 传入的 hint
  @available(iOS 13.0, *)
  private func resolveLastSaveDirectory(hint: String) -> URL? {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: AppDelegate.lastSaveDirKey) {
      var stale = false
      if let url = try? URL(
        resolvingBookmarkData: data,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      ), !stale {
        // 目录仍存在才用（被用户删除/移走时改用兜底）
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
           isDir.boolValue {
          return url
        }
      }
    }
    let savedPath = defaults.string(forKey: AppDelegate.lastSaveDirPathKey) ?? ""
    let candidates = [savedPath, hint].filter { !$0.isEmpty }
    for p in candidates {
      var isDir: ObjCBool = false
      if FileManager.default.fileExists(atPath: p, isDirectory: &isDir),
         isDir.boolValue {
        return URL(fileURLWithPath: p)
      }
    }
    // 都没有：拉到「我的 iPhone」根（iCloud 不可用时 UIDocumentPicker 自行兜底）
    if let docs = FileManager.default.urls(
      for: .documentDirectory,
      in: .userDomainMask
    ).first {
      return docs.deletingLastPathComponent()
    }
    return nil
  }



  /// 记录本次保存的目录（路径 + bookmark），供下次打开面板时定位
  private func rememberSaveDirectory(of fileURL: URL) {
    let dirURL = fileURL.deletingLastPathComponent()
    let defaults = UserDefaults.standard
    defaults.set(dirURL.path, forKey: AppDelegate.lastSaveDirPathKey)
    if #available(iOS 13.0, *) {
      if let data = try? dirURL.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      ) {
        defaults.set(data, forKey: AppDelegate.lastSaveDirKey)
      }
    }
  }

  /// 文件名清洗：去掉路径分隔符与 iOS 不接受的控制字符
  private static func sanitizeFileName(_ name: String) -> String {
    var out = name
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "\\", with: "_")
      .replacingOccurrences(of: ":", with: "_")
    if out.isEmpty { out = "qinglong_export.txt" }
    if out.count > 120 {
      out = String(out.prefix(120))
    }
    return out
  }

  private func cleanupPendingExport() {
    if let url = pendingExportURL {
      try? FileManager.default.removeItem(at: url)
    }
    pendingExportURL = nil
  }

  private func presentFilePicker(
    from controller: UIViewController,
    multiple: Bool,
    result: @escaping FlutterResult
  ) {
    // 上一次选择未结束，直接拒绝新的请求，避免 result 被覆盖导致挂起
    if filePickerResult != nil {
      result(nil)
      return
    }
    filePickerResult = result
    filePickerMultiple = multiple

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(
        forOpeningContentTypes: [UTType.item],
        asCopy: true
      )
    } else {
      picker = UIDocumentPickerViewController(
        documentTypes: ["public.item"],
        in: .import
      )
    }
    picker.delegate = self
    picker.allowsMultipleSelection = multiple
    controller.present(picker, animated: true)
  }

  /// 将选中的文件拷贝到应用沙盒内的固定目录后回传，保证 Dart 侧后续始终可读
  private func copyToSandbox(_ url: URL) -> [String: String]? {
    let fileName = url.lastPathComponent
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("picked_files")
    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      let destURL = tempDir.appendingPathComponent(fileName)
      if FileManager.default.fileExists(atPath: destURL.path) {
        try? FileManager.default.removeItem(at: destURL)
      }

      let scoped = url.startAccessingSecurityScopedResource()
      defer {
        if scoped { url.stopAccessingSecurityScopedResource() }
      }

      try FileManager.default.copyItem(at: url, to: destURL)
      return ["path": destURL.path, "name": fileName]
    } catch {
      return nil
    }
  }

  private func finishPicker(_ payload: [String: String]?) {
    let result = filePickerResult
    filePickerResult = nil
    filePickerMultiple = false
    result?(payload)
  }

  /// 多选结束：回传 [{path, name}]，未选到文件时回传空数组
  private func finishPickerList(_ payload: [[String: String]]) {
    let result = filePickerResult
    filePickerResult = nil
    filePickerMultiple = false
    result?(payload)
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    // 保存（导出）模式：没有 pickFiles 标记但有 pendingExportURL
    if !filePickerMultiple && pendingExportURL != nil {
      let exported = urls.first
      let result = filePickerResult
      filePickerResult = nil
      cleanupPendingExport()
      if let url = exported {
        rememberSaveDirectory(of: url)
        result?([
          "path": url.path,
          "name": url.lastPathComponent,
        ])
      } else {
        result?(nil)
      }
      return
    }
    if filePickerMultiple {
      finishPickerList(urls.compactMap { copyToSandbox($0) })
      return
    }
    guard let url = urls.first else {
      finishPicker(nil)
      return
    }
    finishPicker(copyToSandbox(url))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    // 保存面板取消：清理临时文件并回传 nil（调用方据此提示"已取消"）
    cleanupPendingExport()
    let multiple = filePickerMultiple
    let result = filePickerResult
    filePickerResult = nil
    filePickerMultiple = false
    result?(multiple ? [] : nil)
  }
}
