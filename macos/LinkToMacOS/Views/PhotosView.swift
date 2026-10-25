import AppKit
import LinkCore
import SwiftUI

/// 照片网格：按天分组，缩放滑块，单击选择，双击大图，右键 / ⌘C / 拖拽导出。
struct PhotosView: View {
    let library: PhoneLibrary
    let title: Text

    @State private var model: MediaListModel
    @State private var selection: Set<Int64> = []
    @State private var anchor: Int64?
    @State private var viewing: Int64?
    @AppStorage("photoCellSize") private var cellSize: Double = 140

    init(library: PhoneLibrary, title: Text, album: Int64?, kind: MediaKind) {
        self.library = library
        self.title = title
        _model = State(initialValue: MediaListModel(remote: library.remote, album: album, kind: kind))
    }

    var body: some View {
        Group {
            if !library.mediaAllowed {
                ContentUnavailableView {
                    Label("无法读取相册", systemImage: "lock.shield")
                } description: {
                    Text("请在手机上打开 LinkToMacOS，授予“相册读取”权限（选择“允许全部”），然后回到这里。")
                } actions: {
                    Button("重新检查") { Task { await library.refreshOverview() } }
                }
            } else {
                content
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(model.total > 0 ? "\(model.total) 项" : "")
        .toolbar {
            ToolbarItemGroup {
                Button { copy(selectedItems) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                    .disabled(selection.isEmpty)
                    .help("拷贝所选项目（⌘C），可在访达里粘贴")
                Button { saveTo(selectedItems) } label: { Label("存储到…", systemImage: "square.and.arrow.down") }
                    .disabled(selection.isEmpty)
                    .help("把所选项目存储到 Mac")
                Image(systemName: "photo").imageScale(.small).foregroundStyle(.secondary)
                Slider(value: $cellSize, in: 90...280).frame(width: 110).help("缩放")
                Image(systemName: "photo").imageScale(.large).foregroundStyle(.secondary)
                Button {
                    Task {
                        await library.refreshOverview()
                        await model.reload()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新（⌘R）")
                .keyboardShortcut("r")
            }
        }
        .task(id: library.mediaAllowed) {
            if library.mediaAllowed { await model.loadMore() }
        }
        .background(ShortcutMonitor(
            isEnabled: viewing == nil,
            onCopy: { copy(selectedItems) },
            onSelectAll: { selection = Set(model.items.map(\.id)) },
            onSpace: {
                // 空格预览：最后点的那张，否则所选的第一张
                if let anchor, selection.contains(anchor) { viewing = anchor }
                else { viewing = model.items.first { selection.contains($0.id) }?.id }
            }))
        .overlay {
            if viewing != nil {
                PhotoViewer(
                    library: library, model: model, currentId: $viewing,
                    onSave: { saveTo([$0]) }, onCopy: { copy([$0]) })
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewing)
    }

    private var content: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize), spacing: 2)],
                spacing: 2, pinnedViews: [.sectionHeaders]
            ) {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            ThumbnailCell(library: library, item: item, size: cellSize, selected: selection.contains(item.id))
                                .onTapGesture(count: 2) { viewing = item.id }
                                .onTapGesture { click(item) }
                                .contextMenu { menu(for: item) }
                                .onDrag { library.exporter.promise(for: .init(media: item)) }
                                .onAppear { model.loadMoreIfNeeded(at: item) }
                        }
                    } header: {
                        DayHeader(day: group.day, count: group.items.count)
                    }
                }
            }
            .padding(.horizontal, 2)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { selection = [] } }
            if model.isLoading {
                ProgressView().controlSize(.small).padding(20)
            }
        }
        .overlay {
            if model.isEmpty {
                ContentUnavailableView("没有照片", systemImage: "photo.on.rectangle")
            } else if let error = model.error, model.items.isEmpty {
                ContentUnavailableView {
                    Label("无法加载", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await model.reload() } }
                }
            }
        }
    }

    // MARK: 选择

    private var selectedItems: [MediaItem] {
        model.items.filter { selection.contains($0.id) }
    }

    private func click(_ item: MediaItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
            anchor = item.id
        } else if flags.contains(.shift), let anchor, let a = model.index(of: anchor), let b = model.index(of: item.id) {
            selection = Set(model.items[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [item.id]
            anchor = item.id
        }
    }

    /// 右键的项目在选择里就操作整个选择，否则只操作它自己。
    private func targets(for item: MediaItem) -> [MediaItem] {
        selection.contains(item.id) ? selectedItems : [item]
    }

    @ViewBuilder
    private func menu(for item: MediaItem) -> some View {
        Button(item.isVideo ? "播放" : "打开") { viewing = item.id }
        Divider()
        Button("拷贝") { copy(targets(for: item)) }
        Button("存储到…") { saveTo(targets(for: item)) }
    }

    // MARK: 导出

    private func copy(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        run { try await library.exporter.copyToPasteboard(items.map(ExportService.Item.init(media:))) }
    }

    private func saveTo(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1, let item = items.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = item.name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            run { try await library.exporter.saveAs(.init(media: item), to: url) }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = String(localized: "存到这里")
            panel.message = String(localized: "选择用来保存 \(items.count) 个项目的文件夹")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            run { try await library.exporter.save(items.map(ExportService.Item.init(media:)), to: url) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { library.report(error) }
        }
    }
}

private struct DayHeader: View {
    let day: Date
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day, format: .dateTime.year().month().day().weekday(.wide))
                .font(.title3.weight(.semibold))
            Text("\(count) 项").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

private struct ThumbnailCell: View {
    let library: PhoneLibrary
    let item: MediaItem
    let size: Double
    let selected: Bool
    @State private var image: NSImage?

    init(library: PhoneLibrary, item: MediaItem, size: Double, selected: Bool) {
        self.library = library
        self.item = item
        self.size = size
        self.selected = selected
        _image = State(initialValue: library.thumbnails.cached(id: item.id, size: Self.pixels(for: size)))
    }

    /// 缩略图只请求两档像素，缩放滑块来回拖动时能复用缓存。
    private static func pixels(for size: Double) -> Int { size > 170 ? 512 : 320 }

    var body: some View {
        Color(nsColor: .quaternarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").imageScale(.small)
                        Text(Self.format(duration: item.duration))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(6)
                }
            }
            .overlay {
                if selected { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) }
            }
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .font(.title3)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
            .task(id: Self.pixels(for: size)) {
                let pixels = Self.pixels(for: size)
                if let cached = library.thumbnails.cached(id: item.id, size: pixels) {
                    image = cached
                } else if let loaded = await library.thumbnails.image(id: item.id, isVideo: item.isVideo, size: pixels) {
                    image = loaded
                }
            }
    }

    private static func format(duration ms: Int64) -> String {
        let seconds = Int(ms / 1000)
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
