import Foundation
import AVFoundation
import CoreLocation
import CoreMotion
import Contacts
import EventKit
import Photos
import UIKit
import UserNotifications

// MARK: - 能力清单

enum CapabilityKind: String, CaseIterable, Codable, Identifiable {
    case deviceInfo
    case fileSandbox
    case clipboard
    case motion
    case photoLibrary
    case camera
    case microphone
    case location
    case contacts
    case calendar
    case reminders
    case notifications
    case shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deviceInfo: return "设备档案"
        case .fileSandbox: return "文件读写"
        case .clipboard: return "剪贴板"
        case .motion: return "运动传感器"
        case .photoLibrary: return "相册"
        case .camera: return "相机"
        case .microphone: return "麦克风"
        case .location: return "定位"
        case .contacts: return "通讯录"
        case .calendar: return "日历"
        case .reminders: return "提醒事项"
        case .notifications: return "通知"
        case .shell: return "终端"
        }
    }

    var detail: String {
        switch self {
        case .deviceInfo: return "型号、系统、电量、内存、存储、网络"
        case .fileSandbox: return "读写 App 文档目录内的文件"
        case .clipboard: return "读写剪贴板文本"
        case .motion: return "加速度、陀螺仪实时数据"
        case .photoLibrary: return "读取相册图片并复制到沙盒"
        case .camera: return "授权相机（供拍照使用）"
        case .microphone: return "授权麦克风"
        case .location: return "当前经纬度"
        case .contacts: return "按姓名搜索联系人"
        case .calendar: return "查询近期日程"
        case .reminders: return "创建提醒事项"
        case .notifications: return "发本地通知提醒"
        case .shell:
            if LocalShell.isAvailable { return "本机真实终端（内置 BusyBox，无沙盒）" }
            return "命令模拟（沙盒内）/ 远程执行器"
        }
    }

    var icon: String {
        switch self {
        case .deviceInfo: return "iphone.gen3"
        case .fileSandbox: return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .motion: return "gyroscope"
        case .photoLibrary: return "photo.stack"
        case .camera: return "camera"
        case .microphone: return "mic"
        case .location: return "location"
        case .contacts: return "person.crop.circle"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .notifications: return "bell"
        case .shell: return "terminal"
        }
    }

    /// 需要系统弹窗授权
    var needsSystemPermission: Bool {
        switch self {
        case .photoLibrary, .camera, .microphone, .location,
             .contacts, .calendar, .reminders, .notifications:
            return true
        default:
            return false
        }
    }

    /// 高敏感能力
    var isSensitive: Bool {
        switch self {
        case .microphone, .location, .contacts, .shell:
            return true
        default:
            return false
        }
    }
}

enum PermissionState: String {
    case granted
    case denied
    case notDetermined
    case unavailable

    var title: String {
        switch self {
        case .granted: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未授权"
        case .unavailable: return "不可用"
        }
    }
}

// MARK: - 定位

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func current() async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.continuation?.resume(returning: locations.last)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}

// MARK: - 权限中心

@MainActor
final class PermissionCenter: ObservableObject {
    @Published private(set) var states: [CapabilityKind: PermissionState] = [:]
    @Published var shellEnabled: Bool = (UserDefaults.standard.object(forKey: "aichat.shell.enabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(shellEnabled, forKey: "aichat.shell.enabled") }
    }
    @Published var requesting: CapabilityKind?

    init() {
        refresh()
    }

    func state(_ kind: CapabilityKind) -> PermissionState {
        states[kind] ?? .notDetermined
    }

    /// 用户可以交给模型的全部能力
    var enabledKinds: [CapabilityKind] {
        var result: [CapabilityKind] = []
        for kind in CapabilityKind.allCases {
            if kind == .shell {
                if shellEnabled { result.append(kind) }
                continue
            }
            let current = state(kind)
            if current == .granted || (current == .notDetermined && !kind.needsSystemPermission) {
                result.append(kind)
            }
        }
        return result
    }

    /// 设置页展示用：真正授权的系统权限
    func refresh() {
        states[.deviceInfo] = .granted
        states[.fileSandbox] = .granted
        states[.clipboard] = .granted
        states[.motion] = CMMotionManager().isDeviceMotionAvailable ? .granted : .unavailable

        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: states[.photoLibrary] = .granted
        case .denied, .restricted: states[.photoLibrary] = .denied
        default: states[.photoLibrary] = .notDetermined
        }

        states[.camera] = map(AVCaptureDevice.authorizationStatus(for: .video))
        states[.microphone] = map(AVCaptureDevice.authorizationStatus(for: .audio))
        states[.location] = map(LocationProvider.shared.status)
        states[.contacts] = map(CNContactStore.authorizationStatus(for: .contacts))
        states[.calendar] = map(EKEventStore.authorizationStatus(for: .event))
        states[.reminders] = map(EKEventStore.authorizationStatus(for: .reminder))
        states[.shell] = .granted

        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.states[.notifications] = .granted
            case .denied:
                self.states[.notifications] = .denied
            default:
                self.states[.notifications] = .notDetermined
            }
        }
    }

    func request(_ kind: CapabilityKind) async {
        requesting = kind

        switch kind {
        case .photoLibrary:
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .location:
            LocationProvider.shared.requestAuthorization()
            try? await Task.sleep(nanoseconds: 800_000_000)
        case .contacts:
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        case .calendar:
            let store = EKEventStore()
            if #available(iOS 17.0, *) {
                _ = try? await store.requestFullAccessToEvents()
            } else {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    store.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .reminders:
            let store = EKEventStore()
            if #available(iOS 17.0, *) {
                _ = try? await store.requestFullAccessToReminders()
            } else {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    store.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        case .notifications:
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        default:
            break
        }

        requesting = nil
        refresh()
    }

    // MARK: 映射

    private func map(_ status: PHAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .limited: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func map(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func map(_ status: CNAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    private func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        default:
            if #available(iOS 17.0, *) {
                if status == .fullAccess { return .granted }
                if status == .writeOnly { return .denied }
            }
            return .notDetermined
        }
    }
}