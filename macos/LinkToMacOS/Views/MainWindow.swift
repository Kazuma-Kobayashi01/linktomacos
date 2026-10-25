import LinkCore
import SwiftUI

enum SidebarItem: Hashable {
    case overview
    case mirror
    case library
    case videos
    case apps
    case album(Int64)
    /// 相对于手机内部存储根目录的文件夹。
    case files(String)
}

/// 主窗口：左侧是 macOS 标准的半透明侧边栏（毛玻璃），右侧是内容。
struct MainWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let selection = model.sidebarSelection
        NavigationSplitView {
            SidebarView(selection: $model.sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            DetailRouter(item: selection ?? .overview)
                .id(selection)
        }
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            // 菜单栏常驻程序：打开窗口时才出现在 Dock 里
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 用户可能刚在手机上授了权，回到 Mac 时刷新
            Task { await model.activeLibrary?.refreshOverview() }
        }
    }
}

private struct DetailRouter: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem

    var body: some View {
        if item == .overview {
            if let monitor = model.activeMonitor {
                OverviewView(monitor: monitor)
            } else {
                DisconnectedView()
            }
        } else if let library = model.activeLibrary {
            DetailView(library: library, item: item)
                .overlay(alignment: .bottom) { TransferHUD(center: library.transfers) }
        } else {
            DisconnectedView()
        }
    }
}

private struct DetailView: View {
    @Bindable var library: PhoneLibrary
    let item: SidebarItem

    var body: some View {
        Group {
            switch item {
            case .overview:
                EmptyView()
            case .mirror:
                MirrorPage(library: library)
            case .library:
                PhotosView(library: library, title: Text("所有项目"), album: nil, kind: .all)
            case .videos:
                PhotosView(library: library, title: Text("视频"), album: nil, kind: .video)
            case .apps:
                AppsView(library: library)
            case .album(let id):
                PhotosView(library: library, title: library.albums.first { $0.id == id }.map { Text(verbatim: $0.name) } ?? Text("相簿"), album: id, kind: .all)
            case .files(let path):
                FilesView(library: library, startPath: path)
            }
        }
        .alert("操作失败", isPresented: Binding(get: { library.alertMessage != nil }, set: { if !$0 { library.alertMessage = nil } })) {
            Button("好") {}
        } message: {
            Text(library.alertMessage ?? "")
        }
    }
}

private struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?
    @AppStorage("sidebarAlbumsExpanded") private var albumsExpanded = true

    private let folders: [(title: LocalizedStringKey, path: String, icon: String)] = [
        ("内部存储", "", "internaldrive"),
        ("下载", "Download", "arrow.down.circle"),
        ("文稿", "Documents", "doc"),
        ("相机", "DCIM", "camera"),
        ("图片", "Pictures", "photo"),
        ("音乐", "Music", "music.note"),
    ]

    var body: some View {
        List(selection: $selection) {
            if let monitor = model.activeMonitor {
                Section { DeviceHeader(monitor: monitor).selectionDisabled() }
                Section {
                    Label("概览", systemImage: "gauge.with.dots.needle.67percent").tag(SidebarItem.overview)
                    if model.activeLibrary != nil {
                        Label("投屏", systemImage: "rectangle.on.rectangle").tag(SidebarItem.mirror)
                    }
                }
            }
            if let library = model.activeLibrary {
                Section("资料库") {
                    Label("所有项目", systemImage: "photo.on.rectangle")
                        .badge(library.imageCount + library.videoCount)
                        .tag(SidebarItem.library)
                    Label("视频", systemImage: "video")
                        .badge(library.videoCount)
                        .tag(SidebarItem.videos)
                    Label("应用", systemImage: "square.grid.2x2").tag(SidebarItem.apps)
                }
                Section("文件") {
                    ForEach(folders, id: \.path) { folder in
                        Label(folder.title, systemImage: folder.icon).tag(SidebarItem.files(folder.path))
                    }
                }
                if !library.albums.isEmpty {
                    Section("相簿", isExpanded: $albumsExpanded) {
                        ForEach(library.albums) { album in
                            Label(album.name, systemImage: "rectangle.stack")
                                .badge(album.count)
                                .tag(SidebarItem.album(album.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct DeviceHeader: View {
    let monitor: DeviceMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.name).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(monitor.isOnline ? Color.green : Color.gray).frame(width: 6, height: 6)
                    if !monitor.isOnline {
                        Text("离线")
                    } else if let status = monitor.status {
                        Text("已连接 · 电量 \(status.batteryLevel)%")
                    } else {
                        Text("已连接")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DisconnectedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentUnavailableView {
            Label("手机未连接", systemImage: "iphone.slash")
        } description: {
            Text(model.pairedDevices.isEmpty
                 ? "还没有配对手机。点下面的按钮，用手机扫码配对。"
                 : "请确认手机和这台 Mac 在同一个网络，并且手机上的 LinkToMacOS 正在运行。")
        } actions: {
            if model.pairedDevices.isEmpty {
                Button("配对新手机…") {
                    model.beginPairing()
                    openWindow(id: WindowID.pairing)
                }
            }
        }
    }
}

/// 窗口底部的下载进度条。
private struct TransferHUD: View {
    let center: TransferCenter

    var body: some View {
        if !center.active.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(center.active) { transfer in
                    HStack(spacing: 10) {
                        ProgressView(value: transfer.fraction).progressViewStyle(.circular).controlSize(.small)
                        Text(transfer.name).lineLimit(1)
                        if transfer.total > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: transfer.completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .shadow(radius: 8, y: 2)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
