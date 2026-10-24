import AppKit
import LinkCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class FilesModel {
    private let remote: PhoneRemote
    private(set) var path: String
    private(set) var entries: [FileEntry] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    init(remote: PhoneRemote, path: String) {
        self.remote = remote
        self.path = path
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { !path.isEmpty }

    var folderName: String {
        path.isEmpty ? "内部存储" : (path as NSString).lastPathComponent
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let listing = try await remote.directory(path)
            entries = listing.entries
            error = nil
        } catch is CancellationError {
        } catch {
            entries = []
            self.error = error.localizedDescription
        }
    }

    func go(to newPath: String) async {
        guard newPath != path else { return }
        backStack.append(path)
        forwardStack = []
        path = newPath
        await load()
    }

    func goBack() async {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(path)
        path = previous
        await load()
    }

    func goForward() async {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(path)
        path = next
        await load()
    }

    func goUp() async {
        await go(to: (path as NSString).deletingLastPathComponent)
    }

    func child(_ name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }
}

/// 手机文件浏览：类似访达的列表视图，支持前进后退、排序、右键 / ⌘C / 拖拽导出。
struct FilesView: View {
    let library: PhoneLibrary

    @State private var model: FilesModel
    @State private var selection: Set<String> = []
    @State private var sortOrder = [KeyPathComparator(\FileEntry.name, comparator: .localizedStandard)]

    init(library: PhoneLibrary, startPath: String) {
        self.library = library
        _model = State(initialValue: FilesModel(remote: library.remote, path: startPath))
    }

    private var sortedEntries: [FileEntry] {
        let sorted = model.entries.sorted(using: sortOrder)
        return sorted.filter(\.isDir) + sorted.filter { !$0.isDir }
    }

    private var selectedEntries: [FileEntry] {
        model.entries.filter { selection.contains($0.id) }
    }

    var body: some View {
        Group {
            if !library.filesAllowed {
                ContentUnavailableView {
                    Label("无法读取文件", systemImage: "lock.shield")
                } description: {
                    Text("请在手机上打开 LinkToMacOS，授予“所有文件访问”权限，然后回到这里。")
                } actions: {
                    Button("重新检查") { Task { await library.refreshOverview() } }
                }
            } else {
                table
            }
        }
        .navigationTitle(model.folderName)
        .navigationSubtitle(model.path.isEmpty ? "手机 / 内部存储" : "手机 / 内部存储 / " + model.path.replacingOccurrences(of: "/", with: " / "))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { Task { await model.goBack() } } label: { Label("后退", systemImage: "chevron.left") }
                    .disabled(!model.canGoBack)
                Button { Task { await model.goForward() } } label: { Label("前进", systemImage: "chevron.right") }
                    .disabled(!model.canGoForward)
            }
            ToolbarItemGroup {
                Button { copy(selectedEntries) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                    .disabled(selectedEntries.allSatisfy(\.isDir))
                    .help("拷贝所选文件（⌘C），可在访达里粘贴")
                Button { saveTo(selectedEntries.filter { !$0.isDir }) } label: { Label("存储到…", systemImage: "square.and.arrow.down") }
                    .disabled(selectedEntries.allSatisfy(\.isDir))
                    .help("把所选文件存储到 Mac")
                Button { Task { await model.goUp() } } label: { Label("上一级", systemImage: "arrow.up") }
                    .disabled(!model.canGoUp)
                    .help("上一级文件夹")
                Button { Task { await model.load() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .help("刷新")
            }
        }
        .task(id: library.filesAllowed) {
            if library.filesAllowed { await model.load() }
        }
        .onChange(of: model.path) { selection = [] }
        .background(ShortcutMonitor(
            onCopy: { copy(selectedEntries) },
            onSelectAll: { selection = Set(model.entries.map(\.id)) }))
    }

    private var table: some View {
        Table(of: FileEntry.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { entry in
                HStack(spacing: 6) {
                    Image(nsImage: FileIcons.icon(for: entry)).resizable().frame(width: 18, height: 18)
                    Text(entry.name).lineLimit(1)
                }
            }
            .width(min: 180, ideal: 320)
            TableColumn("修改日期", value: \.modified) { entry in
                Text(entry.modifiedDate, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)
            TableColumn("大小", value: \.size) { entry in
                Text(entry.isDir ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
            TableColumn("种类") { entry in
                Text(FileIcons.kind(for: entry)).foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 110)
        } rows: {
            ForEach(sortedEntries) { entry in
                TableRow(entry)
                    .itemProvider {
                        entry.isDir ? nil : library.exporter.promise(for: .init(file: entry, directory: model.path))
                    }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let entries = model.entries.filter { ids.contains($0.id) }
            if entries.count == 1, let entry = entries.first {
                Button(entry.isDir ? "打开文件夹" : "打开") { open(entry) }
                Divider()
            }
            let files = entries.filter { !$0.isDir }
            Button("拷贝") { copy(files) }.disabled(files.isEmpty)
            Button("存储到…") { saveTo(files) }.disabled(files.isEmpty)
        } primaryAction: { ids in
            if let entry = model.entries.first(where: { ids.contains($0.id) }), ids.count == 1 { open(entry) }
        }
        .overlay {
            if let error = model.error {
                ContentUnavailableView {
                    Label("无法读取这个文件夹", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await model.load() } }
                }
            } else if model.entries.isEmpty, !model.isLoading {
                ContentUnavailableView("文件夹是空的", systemImage: "folder")
            } else if model.isLoading, model.entries.isEmpty {
                ProgressView()
            }
        }
    }

    // MARK: 操作

    private func open(_ entry: FileEntry) {
        if entry.isDir {
            Task { await model.go(to: model.child(entry.name)) }
        } else {
            run { try await library.exporter.open(.init(file: entry, directory: model.path)) }
        }
    }

    private func copy(_ files: [FileEntry]) {
        let files = files.filter { !$0.isDir }
        guard !files.isEmpty else { return }
        run { try await library.exporter.copyToPasteboard(files.map { .init(file: $0, directory: model.path) }) }
    }

    private func saveTo(_ files: [FileEntry]) {
        guard !files.isEmpty else { return }
        let directory = model.path
        if files.count == 1, let file = files.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            run { try await library.exporter.saveAs(.init(file: file, directory: directory), to: url) }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "存储"
            panel.message = "选择用来保存 \(files.count) 个文件的文件夹"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            run { try await library.exporter.save(files.map { .init(file: $0, directory: directory) }, to: url) }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            do { try await work() } catch { library.report(error) }
        }
    }
}

/// 文件图标和种类。按扩展名缓存。
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for entry: FileEntry) -> NSImage {
        let ext = entry.isDir ? "/" : (entry.name as NSString).pathExtension.lowercased()
        if let cached = cache[ext] { return cached }
        let type: UTType = entry.isDir ? .folder : (UTType(filenameExtension: ext) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        cache[ext] = icon
        return icon
    }

    static func kind(for entry: FileEntry) -> String {
        if entry.isDir { return "文件夹" }
        let ext = (entry.name as NSString).pathExtension
        return UTType(filenameExtension: ext)?.localizedDescription ?? (ext.isEmpty ? "文件" : "\(ext.uppercased()) 文件")
    }
}
