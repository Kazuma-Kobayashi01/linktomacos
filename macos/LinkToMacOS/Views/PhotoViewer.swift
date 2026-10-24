import AppKit
import LinkCore
import SwiftUI

/// 大图预览：覆盖在照片网格上，← → 切换，空格或 Esc 关闭。视频点播放后下载并用默认播放器打开。
struct PhotoViewer: View {
    let library: PhoneLibrary
    let model: MediaListModel
    @Binding var currentId: Int64?
    let onSave: (MediaItem) -> Void
    let onCopy: (MediaItem) -> Void

    @State private var image: NSImage?
    @State private var failed = false
    @FocusState private var focused: Bool

    private var index: Int? { currentId.flatMap { model.index(of: $0) } }
    private var current: MediaItem? { index.map { model.items[$0] } }

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()

            if let current {
                ZStack {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else if failed {
                        Label("无法加载", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                    if current.isVideo {
                        Button { play(current) } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.45))
                                .shadow(radius: 6)
                        }
                        .buttonStyle(.plain)
                        .help("下载并用默认播放器打开")
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 56)
                .shadow(radius: 12)
            }

            HStack {
                navButton("chevron.left", enabled: (index ?? 0) > 0) { step(-1) }
                Spacer()
                navButton("chevron.right", enabled: (index ?? 0) < model.items.count - 1) { step(1) }
            }
            .padding(.horizontal, 14)

            VStack {
                topBar
                Spacer()
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { currentId = nil; return .handled }
        .onKeyPress(.space) { currentId = nil; return .handled }
        .task(id: currentId) { await load() }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { currentId = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered).controlSize(.large).help("关闭")
            if let current {
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.name).font(.headline).lineLimit(1)
                    Text(current.dateValue, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let current {
                Button("拷贝") { onCopy(current) }
                Button("存储到…") { onSave(current) }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func navButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2.weight(.semibold)).frame(width: 36, height: 56)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.25)
        .disabled(!enabled)
    }

    private func step(_ delta: Int) {
        guard let index else { return }
        let next = index + delta
        guard model.items.indices.contains(next) else { return }
        currentId = model.items[next].id
        model.loadMoreIfNeeded(at: model.items[next])
    }

    private func play(_ item: MediaItem) {
        Task {
            do { try await library.exporter.open(.init(media: item)) } catch { library.report(error) }
        }
    }

    /// 先用缓存里的小图占位，再换成大图。
    private func load() async {
        guard let item = current else { return }
        failed = false
        image = library.thumbnails.cached(id: item.id, size: 512) ?? library.thumbnails.cached(id: item.id, size: 320)
        if let large = await library.thumbnails.preview(id: item.id, isVideo: item.isVideo) {
            image = large
        } else if image == nil, !Task.isCancelled {
            failed = true
        }
    }
}
