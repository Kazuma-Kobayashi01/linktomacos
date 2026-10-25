import CoreImage.CIFilterBuiltins
import SwiftUI

struct PairingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 16) {
            if let pairing = model.pairing {
                Text("用手机上的 LinkToMacOS 扫描二维码").font(.headline)
                if let image = qrImage(pairing.payload.uri) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(pairing.expires.timeIntervalSince(context.date)))
                    let minutes = remaining / 60
                    let seconds = String(format: "%02d", remaining % 60)
                    let message: LocalizedStringKey = remaining > 0 ? "二维码将在 \(minutes):\(seconds) 后失效" : "二维码已失效"
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(pairing.payload.hosts.joined(separator: " · ") + " : \(pairing.payload.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("刷新") { model.beginPairing() }
                    Button("复制配对链接") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(pairing.payload.uri, forType: .string)
                    }
                }
            } else if !model.connected.isEmpty {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                Text("已连接").font(.headline)
                Button("完成") { dismissWindow(id: WindowID.pairing) }
            } else {
                ProgressView()
                Button("生成二维码") { model.beginPairing() }
            }
            if let reason = model.lastRejection {
                Text("最近一次连接被拒绝：\(reason)").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onDisappear { if model.pairing != nil { model.cancelPairing() } }
    }

    private func qrImage(_ string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: output.extent.size)
    }
}
