import LinkCore
import SwiftUI

/// 菜单栏弹出的面板：顶部是连接状态，中间是手机卡片和 AirSend，下面是菜单行，最底下是端口。
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showPaired = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            VStack(spacing: 10) {
                if model.connected.isEmpty {
                    EmptyCard(hasPairedDevices: !model.pairedDevices.isEmpty) { pair() }
                } else {
                    ForEach(Array(model.connected.values)) { DeviceCard(device: $0) }
                    sendFilesButton
                }
            }
            .padding(.horizontal, 12)

            Divider().padding(.horizontal, 12).padding(.vertical, 10)

            VStack(spacing: 2) {
                MenuRow(title: "打开主窗口", icon: "macwindow", shortcut: "⌘0") {
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                }
                if !model.connected.isEmpty {
                    MenuRow(title: "配对新手机…", icon: "qrcode") { pair() }
                }
                if !model.pairedDevices.isEmpty {
                    // 点开后在下面列出已配对的手机，每台一行“取消配对”（不用系统菜单，免得和别的行对不齐）
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showPaired.toggle() }
                    } label: {
                        MenuRowLabel(title: "已配对设备", icon: "iphone.gen3", trailing: showPaired ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                    if showPaired {
                        ForEach(model.pairedDevices) { device in
                            Button(role: .destructive) {
                                model.unpair(device)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "link.badge.minus").frame(width: 18)
                                    Text("取消配对 \(device.name)").lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.red)
                                .padding(.leading, 30)
                                .padding(.trailing, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                MenuRow(title: "设置…", icon: "gearshape", shortcut: "⌘,") {
                    NSApp.activate()
                    openSettings()
                }
            }
            .padding(.horizontal, 6)

            Divider().padding(.horizontal, 12).padding(.vertical, 8)

            VStack(spacing: 2) {
                MenuRow(title: "退出", icon: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 6)

            footer
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(width: 320)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image("MenuBarLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 18)
                .foregroundStyle(.primary)
            Text("Link to macOS").font(.headline)
            Spacer()
            connectionPill
        }
    }

    /// 连接状态：绿点已连接，灰点没连上或没配对。
    private var connectionPill: some View {
        let connected = !model.connected.isEmpty
        return HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
            if connected {
                Text("已连接")
            } else if model.pairedDevices.isEmpty {
                Text("尚未配对手机")
            } else {
                Text("手机未连接")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var sendFilesButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = true
            panel.prompt = String(localized: "发送")
            NSApp.activate()
            if panel.runModal() == .OK { model.airSend.send(urls: panel.urls) }
        } label: {
            Label("AirSend：发送文件到手机…", systemImage: "paperplane.fill")
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func pair() {
        model.beginPairing()
        openWindow(id: WindowID.pairing)
        NSApp.activate()
    }

    // MARK: 底部

    @ViewBuilder
    private var footer: some View {
        switch model.serverState {
        case .starting:
            Text("启动中…").font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .listening(let port):
            (Text("端口") + Text(verbatim: " \(port)")).font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Text(message).font(.caption2).foregroundStyle(.red).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 菜单行

/// 面板里的一行：图标、标题、右侧快捷键；鼠标移上去有淡淡的高亮，整行都能点。
private struct MenuRow: View {
    let title: LocalizedStringKey
    let icon: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, icon: icon, shortcut: shortcut)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuRowLabel: View {
    let title: LocalizedStringKey
    let icon: String
    var shortcut: String?
    var trailing: String?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer(minLength: 8)
            if let shortcut {
                Text(shortcut).font(.callout).foregroundStyle(.tertiary)
            }
            if let trailing {
                Image(systemName: trailing).font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.09) : Color.clear, in: .rect(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - 手机卡片

private struct DeviceCard: View {
    let device: ConnectedDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BatteryBadge(level: device.status?.batteryLevel, charging: device.status?.charging ?? false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.device.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(device.device.model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let status = device.status {
                chips(status)
                if status.storageTotal > 0 { storage(status) }
            } else {
                Text("等待状态…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 12))
    }

    private func chips(_ status: DeviceStatus) -> some View {
        HStack(spacing: 6) {
            if status.charging {
                Chip(icon: "bolt.fill", tint: .green) { Text("充电中") }
            }
            if status.wifiConnected {
                Chip(icon: "wifi", variable: status.wifiLevel.map { Double($0) / 4 }) { Text(verbatim: "Wi‑Fi") }
            } else if let level = status.signalLevel {
                Chip(icon: "cellularbars", variable: Double(level) / 4) { Text(verbatim: status.networkType ?? "") }
            }
        }
    }

    private func storage(_ status: DeviceStatus) -> some View {
        let used = Double(status.storageTotal - status.storageFree) / Double(status.storageTotal)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule().fill(Color.accentColor.gradient).frame(width: max(6, proxy.size.width * min(1, used)))
                }
            }
            .frame(height: 6)
            Text("存储 剩余 \(ByteCountFormatter.string(fromByteCount: status.storageFree, countStyle: .file))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// 圆环电量，中间是数字。充电是绿色，低电量变橙、变红。
private struct BatteryBadge: View {
    let level: Int?
    let charging: Bool

    private var tint: Color {
        guard let level else { return .gray }
        if charging { return .green }
        return level <= 10 ? .red : level <= 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: Double(level ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(level.map(String.init) ?? "–")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .frame(width: 44, height: 44)
    }
}

/// 一个小标签：图标加文字，圆角胶囊底。
private struct Chip<Label: View>: View {
    let icon: String
    var variable: Double?
    var tint: Color = .secondary
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 4) {
            if let variable {
                Image(systemName: icon, variableValue: variable)
            } else {
                Image(systemName: icon)
            }
            label()
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.08), in: .capsule)
    }
}

/// 没有手机连着时的卡片：没配对过就给一个配对按钮。
private struct EmptyCard: View {
    let hasPairedDevices: Bool
    let pair: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(hasPairedDevices ? "手机未连接" : "尚未配对手机")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !hasPairedDevices {
                Button("配对新手机…", action: pair)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.primary.opacity(0.07), in: .rect(cornerRadius: 12))
    }
}
