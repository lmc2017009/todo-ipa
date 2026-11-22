import Foundation
import UIKit
import UniformTypeIdentifiers

/// 目录授权：用系统「文件」选择器让用户显式授权一个目录（可以是沙盒外、甚至其他 App 在「我的 iPhone」里的文件夹），
/// 之后把授权持久化成 security-scoped bookmark，模型通过 `grant:<标签>/相对路径` 读写。
///
/// 这是 iOS 在「无越狱 / 无 TrollStore」前提下唯一合法的跨沙盒文件通道：
/// - 不需要任何私有 entitlement，普通签名即可生效；
/// - 用户点一次授权，App 重启后仍然有效；
/// - 用户随时可以在「设置 → 已授权目录」里撤销。
/// 一条目录授权记录（放顶层，避免全局 actor 隔离影响 Codable 合成）
struct DirectoryGrantRecord: Codable, Identifiable {
    var label: String
    var bookmark: Data
    var path: String
    var id: String { label }
}

/// 目录授权管理：持久化 security-scoped bookmark、弹出系统选择器、按标签解析路径。
///
/// 这是 iOS 在「无越狱 / 无 TrollStore」前提下唯一合法的跨沙盒文件通道：
/// - 不需要任何私有 entitlement，普通签名即可生效；
/// - 用户点一次授权，App 重启后仍然有效；
/// - 用户随时可以在「设置 → 已授权目录」里撤销。
@MainActor
enum DirectoryGrant {
    typealias Grant = DirectoryGrantRecord

    private static let defaultsKey = "directoryGrants"
    private static var activePaths: Set<String> = []
    private static var pickerDelegate: PickerDelegate?
    private static var presentedPicker: UIDocumentPickerViewController?

    // MARK: - 持久化

    static func all() -> [Grant] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([Grant].self, from: data) else {
            return []
        }
        return list
    }

    private static func store(_ list: [Grant]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func add(label: String, url: URL) -> Grant? {
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else {
            return nil
        }
        let grant = Grant(label: label, bookmark: bookmark, path: url.path)
        var list = all().filter { $0.label != label }
        list.append(grant)
        list.sort { $0.label < $1.label }
        store(list)
        _ = open(grant)
        return grant
    }

    static func remove(label: String) -> Bool {
        var list = all()
        guard let index = list.firstIndex(where: { $0.label == label }) else { return false }
        if let url = open(list[index]) {
            url.stopAccessingSecurityScopedResource()
            activePaths.remove(url.path)
        }
        list.remove(at: index)
        store(list)
        return true
    }

    /// 解析 bookmark 并（首次）开启安全作用域访问
    static func open(_ grant: Grant) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: grant.bookmark,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            return nil
        }
        let key = url.path
        if !activePaths.contains(key) {
            _ = url.startAccessingSecurityScopedResource()
            activePaths.insert(key)
        }
        return url
    }

    static func url(forLabel label: String) -> URL? {
        guard let grant = all().first(where: { $0.label == label }) else { return nil }
        return open(grant)
    }

    /// 摘要行，给 access_report / fs_list 用
    static func summaryLines() -> [String] {
        let list = all()
        if list.isEmpty { return ["（无授权目录）"] }
        return list.map { "grant:\($0.label) → \($0.path)" }
    }

    // MARK: - 选择器

    /// 弹出系统目录选择器，返回用户选中的目录；取消或超时返回 nil
    static func presentPicker(timeout: TimeInterval = 300) async -> URL? {
        guard let host = topViewController() else { return nil }

        return await withCheckedContinuation { continuation in
            let delegate = PickerDelegate { url in
                continuation.resume(returning: url)
            }
            pickerDelegate = delegate

            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder],
                                                        asCopy: false)
            picker.delegate = delegate
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            presentedPicker = picker
            host.present(picker, animated: true)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 5) * 1_000_000_000))
                guard pickerDelegate === delegate else { return }
                presentedPicker?.dismiss(animated: true)
                delegate.finish(nil)
            }
        }
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
            ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// 选择器回调持有者（避免 delegate 提前释放导致 continuation 永不 resume）
final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    private var onFinish: ((URL?) -> Void)?

    init(onFinish: @escaping (URL?) -> Void) {
        self.onFinish = onFinish
    }

    func finish(_ url: URL?) {
        guard let handler = onFinish else { return }
        onFinish = nil
        handler(url)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController,
                        didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }
}