import LinkCore
import SwiftUI

struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if model.connected.isEmpty {
                Text(model.pairedDevices.isEmpty ? "尚未配对手机" : "手机未连接")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(model.connected.values)) { DeviceCard(device: $0) }
            }
            Divider()
            if !model.pairedDevices.isEmpty {
                Menu("已配对设备") {
                    ForEach(model.pairedDevices) { device in
                        Button("取消配对 \(device.name)", role: .destructive) { model.unpair(device) }
                    }
                }
                .menuStyle(.borderlessButton)
            }
            HStack {
                Button("打开主窗口") {
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                }
                Spacer()
                Button("设置…") {
                    NSApp.activate()
                    openSettings()
                }
            }
            HStack {
                Button("配对新手机…") {
                    model.beginPairing()
                    openWindow(id: WindowID.pairing)
                    NSApp.activate()
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("Link to macOS").font(.headline)
            Spacer()
            switch model.serverState {
            case .starting: Text("启动中…").font(.caption).foregroundStyle(.secondary)
            case .listening(let port): Text("端口 \(port)").font(.caption).foregroundStyle(.secondary)
            case .failed(let message): Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
        }
    }
}

private struct DeviceCard: View {
    let device: ConnectedDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "iphone").font(.title2)
                VStack(alignment: .leading) {
                    Text(device.device.name).font(.subheadline.bold())
                    Text(device.device.model).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            if let status = device.status {
                HStack(spacing: 14) {
                    Label("\(status.batteryLevel)%", systemImage: batterySymbol(status))
                    if let level = status.signalLevel {
                        Label {
                            Text(status.networkType ?? "")
                        } icon: {
                            Image(systemName: "cellularbars", variableValue: Double(level) / 4)
                        }
                    }
                    if status.wifiConnected { Image(systemName: "wifi") }
                }
                .font(.caption)
                if status.storageTotal > 0 {
                    let used = Double(status.storageTotal - status.storageFree) / Double(status.storageTotal)
                    ProgressView(value: used) {
                        Text("存储 剩余 \(ByteCountFormatter.string(fromByteCount: status.storageFree, countStyle: .file))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("等待状态…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    private func batterySymbol(_ status: DeviceStatus) -> String {
        if status.charging { return "battery.100percent.bolt" }
        switch status.batteryLevel {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
