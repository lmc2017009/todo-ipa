import SwiftUI
import UIKit

/// 能力中心：把设备权限逐个交给模型
struct CapabilityCenterView: View {
    @EnvironmentObject private var store: ChatStore
    @EnvironmentObject private var permissions: PermissionCenter

    @State private var showDevice = false
    @State private var authorizingAll = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    deviceCard
                    capabilityGrid
                    footnote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .liquidBackdrop()
            .navigationTitle("能力中心")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        permissions.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - 概览

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(permissions.enabledKinds.count)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("/ \(CapabilityKind.allCases.count) 项能力已开放给模型")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            ProgressView(value: Double(permissions.enabledKinds.count),
                         total: Double(CapabilityKind.allCases.count))
                .tint(.accentColor)

            Text("模型能直接读取设备档案、读写沙盒文件、调用终端，以及下面已授权的系统数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(isOn: Binding(
                get: { store.settings.enableTools },
                set: { store.settings.enableTools = $0; store.saveSettings() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("允许模型调用工具")
                        .font(.subheadline.weight(.medium))
                    Text("关闭后模型只能聊天，碰不到设备")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $permissions.shellEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("终端能力")
                        .font(.subheadline.weight(.medium))
                    Text("沙盒模拟终端；填了远程地址就是真 shell")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    authorizeAll()
                } label: {
                    HStack(spacing: 6) {
                        if authorizingAll {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text(authorizingAll ? "授权中…" : "一键授权")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .disabled(authorizingAll)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 24)
    }

    // MARK: - 设备档案

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDevice.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("本机档案")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    CapabilityBadge(title: "自动", icon: "checkmark", tint: .green)
                    Image(systemName: showDevice ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showDevice {
                Text(DeviceProfile.summary())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    UIPasteboard.general.string = DeviceProfile.summary()
                } label: {
                    Label("复制档案", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
    }

    // MARK: - 能力网格

    private var capabilityGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CapabilityKind.allCases) { kind in
                card(kind)
            }
        }
    }

    private func card(_ kind: CapabilityKind) -> some View {
        Button {
            tap(kind)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint(kind))
                        .frame(width: 34, height: 34)
                        .background(tint(kind).opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Spacer(minLength: 0)

                    Circle()
                        .fill(stateColor(kind))
                        .frame(width: 7, height: 7)
                }

                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(kind.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(stateText(kind))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(stateColor(kind))

                    if kind.isSensitive {
                        Image(systemName: "exclamationmark.shield")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .glassSurface(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("说明")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(LocalShell.isAvailable
                 ? "本机已内置真实终端（BusyBox）；若以 TrollStore + no-sandbox 安装，模型可读写全盘并跨 App 读取数据。全盘模式下请只接入可信的模型端点，并留意高危工具二次确认。"
                 : "iOS 的权限只能由系统弹窗授予，App 无法静默开启；被拒绝后需要到系统设置里手动打开。把静态 busybox 放进 App 包或 Documents/bin 后可启用本机真实终端；未内置时终端默认在沙盒内模拟，填写远程地址才会连真实 shell。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - 逻辑

    private func tap(_ kind: CapabilityKind) {
        if kind == .shell {
            permissions.shellEnabled.toggle()
            return
        }

        guard kind.needsSystemPermission else { return }

        let current = permissions.state(kind)
        if current == .denied {
            openSettings()
            return
        }

        Task { await permissions.request(kind) }
    }

    private func authorizeAll() {
        guard !authorizingAll else { return }
        authorizingAll = true

        Task {
            for kind in CapabilityKind.allCases where kind.needsSystemPermission {
                if permissions.state(kind) == .granted { continue }
                await permissions.request(kind)
            }
            permissions.refresh()
            authorizingAll = false
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func stateText(_ kind: CapabilityKind) -> String {
        if kind == .shell {
            return permissions.shellEnabled ? "已开放" : "已关闭"
        }
        if !kind.needsSystemPermission {
            return permissions.state(kind) == .unavailable ? "不可用" : "自动可用"
        }
        return permissions.state(kind).title
    }

    private func stateColor(_ kind: CapabilityKind) -> Color {
        if kind == .shell {
            return permissions.shellEnabled ? .green : .secondary
        }
        if !kind.needsSystemPermission {
            return permissions.state(kind) == .unavailable ? .orange : .green
        }
        switch permissions.state(kind) {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        case .unavailable: return .orange
        }
    }

    private func tint(_ kind: CapabilityKind) -> Color {
        switch kind {
        case .deviceInfo: return .blue
        case .fileSandbox: return .indigo
        case .clipboard: return .teal
        case .motion: return .mint
        case .photoLibrary: return .pink
        case .camera: return .orange
        case .microphone: return .red
        case .location: return .green
        case .contacts: return .cyan
        case .calendar: return .purple
        case .reminders: return .yellow
        case .notifications: return .brown
        case .shell: return .gray
        }
    }
}