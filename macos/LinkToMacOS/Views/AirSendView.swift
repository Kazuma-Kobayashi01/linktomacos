import AppKit
import LinkCore
import SwiftUI
import UniformTypeIdentifiers

/// AirSend：把文件、文字拖到这里发给手机；手机分享过来的文件也在这里留下记录。
struct AirSendView: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    private var service: AirSendService { model.airSend }
    private var phoneName: String { model.activeDevice?.device.name ?? "" }

    static let contentWidth: CGFloat = 640

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                dropZone
                actions
                howItWorks
                history
            }
            .frame(width: Self.contentWidth)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("AirSend")
        .navigationSubtitle(phoneName)
    }

    // MARK: 拖放区

    private var dropZone: some View {
        VStack(spacing: 14) {
            ZStack {
                // 向外扩散的圆环，拖到上面时变大、变亮
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(targeted ? 0.35 - Double(index) * 0.08 : 0.16 - Double(index) * 0.04), lineWidth: 1.5)
                        .frame(width: 84 + CGFloat(index) * 34, height: 84 + CGFloat(index) * 34)
                }
                Circle()
                    .fill(Color.accentColor.gradient)
                    .frame(width: 70, height: 70)
                Image(systemName: targeted ? "arrow.down" : "paperplane.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(height: 154)
            .scaleEffect(targeted ? 1.06 : 1)

            Text(targeted ? "松开发送到手机" : "把文件拖到这里，发给手机")
                .font(.title3.weight(.semibold))
            if !phoneName.isEmpty {
                Label(phoneName, systemImage: "iphone.gen3")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    targeted ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7),
                    style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [7, 5]))
        }
        .animation(.spring(duration: 0.3), value: targeted)
        .onDrop(of: [.fileURL, .plainText], isTargeted: $targeted) { providers in
            handleDrop(providers)
            return true
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button { chooseFiles() } label: { Label("选择文件…", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderedProminent)
            Button { sendClipboard() } label: { Label("发送剪贴板文字", systemImage: "doc.on.clipboard") }
            Spacer()
            Button { NSWorkspace.shared.open(AirSendService.receiveFolder) } label: {
                Label("打开接收文件夹", systemImage: "folder")
            }
        }
        .controlSize(.large)
    }

    // MARK: 使用方法

    private var howItWorks: some View {
        HStack(alignment: .top, spacing: 14) {
            HowToCard(
                systemImage: "arrow.down.to.line", tint: .green,
                title: "从手机发到 Mac",
                detail: "在手机上点“分享”，选 AirSend 或最上面一排的 Mac 名字。文件会存进“下载/AirSend”。")
            HowToCard(
                systemImage: "arrow.up.to.line", tint: .blue,
                title: "从 Mac 发到手机",
                detail: "在访达里右键文件，选“共享 → AirSend”，或者直接拖到上面。")
        }
    }

    // MARK: 最近

    @ViewBuilder
    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近").font(.title3.weight(.semibold))
                Spacer()
                if !service.transfers.isEmpty {
                    Button("清除已完成") { service.clearFinished() }
                        .buttonStyle(.link)
                        .font(.callout)
                }
            }
            if service.transfers.isEmpty {
                Text("传输过的文件会显示在这里。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(service.transfers.enumerated()), id: \.element.id) { index, transfer in
                        if index > 0 { Divider().padding(.leading, 60) }
                        TransferRow(transfer: transfer)
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                }
            }
        }
    }

    // MARK: 操作

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL? = switch item {
                    case let url as URL: url
                    case let data as Data: URL(dataRepresentation: data, relativeTo: nil)
                    default: nil
                    }
                    if let url { Task { @MainActor in service.send(urls: [url]) } }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    if let text = item as? String { Task { @MainActor in service.send(text: text) } }
                }
            }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "发送")
        if panel.runModal() == .OK { service.send(urls: panel.urls) }
    }

    private func sendClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) { service.send(text: text) }
    }
}

/// 一个方向的使用说明：彩色图标、标题、一两句话。
private struct HowToCard: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
    }
}

private struct TransferRow: View {
    let transfer: AirSendService.Transfer

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: fileIcon)
                    .resizable()
                    .frame(width: 34, height: 34)
                Image(systemName: transfer.direction == .send ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, transfer.direction == .send ? Color.blue : Color.green)
                    .font(.system(size: 14))
                    .offset(x: 4, y: 4)
            }
            .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.name).lineLimit(1).truncationMode(.middle)
                switch transfer.state {
                case .running(let fraction):
                    ProgressView(value: fraction).progressViewStyle(.linear)
                case .done:
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if case .done = transfer.state, let location = transfer.location {
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([location]) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 按文件类型显示系统图标。
    private var fileIcon: NSImage {
        let type = UTType(filenameExtension: (transfer.name as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }

    private var detail: String {
        let size = transfer.size > 0 ? ByteCountFormatter.string(fromByteCount: transfer.size, countStyle: .file) + " · " : ""
        let when = transfer.date.formatted(date: .omitted, time: .shortened)
        return size + (transfer.direction == .send ? String(localized: "已发送") : String(localized: "已接收")) + " · " + when
    }
}
