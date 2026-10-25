import LinkCore
import SwiftUI

/// 手机上的应用：点一下就在投屏里打开。还没投屏时会先开始投屏。
struct AppsView: View {
    let library: PhoneLibrary
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    private var session: MirrorSession { model.mirror }

    private var filtered: [PhoneApp] {
        query.isEmpty ? session.apps : session.apps.filter {
            $0.label.localizedCaseInsensitiveContains(query) || $0.package.localizedCaseInsensitiveContains(query)
        }
    }

    private var errorMessage: String? {
        if case .failed(let message) = session.phase { return message }
        return session.launchError
    }

    var body: some View {
        @Bindable var session = model.mirror
        Group {
            if session.serviceReady == true {
                grid
            } else {
                ContentUnavailableView {
                    Label(session.serviceOutdated ? "增强服务需要更新" : "请先启动增强服务", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text(session.serviceOutdated
                         ? "手机上的增强服务还是旧版本。用数据线连接电脑，在“投屏”页重新启动一次。"
                         : "用数据线连接电脑，在“投屏”页启动一次，之后可以拔掉数据线。")
                } actions: {
                    Button("前往投屏页") { model.sidebarSelection = .mirror }
                }
            }
        }
        .navigationTitle("应用")
        .navigationSubtitle(library.deviceName)
        .searchable(text: $query, prompt: "搜索应用")
        .toolbar {
            Picker("模式", selection: $session.mode) {
                Text("独立显示").tag(MirrorMode.newDisplay)
                Text("镜像手机屏幕").tag(MirrorMode.mirror)
            }
            .pickerStyle(.segmented)
            .disabled(session.isRunning || session.isBusy)
            .help(session.mode == .newDisplay
                  ? "应用开在手机的独立显示器上，手机自己的屏幕不受影响"
                  : "应用开在手机屏幕上，并显示在这里；投屏时手机屏幕默认关闭")
        }
        .task {
            await session.loadApps()
            // 页面可见时每 3 秒检查一次增强服务：刚在投屏页启动好，回来就能直接用
            while !Task.isCancelled {
                await session.refreshServiceState()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 12)], spacing: 14) {
                ForEach(filtered) { app in
                    AppCell(app: app, icons: session.icons)
                        .onTapGesture { open(app) }
                        .help(app.package)
                }
            }
            .padding(20)
            if session.apps.isEmpty {
                if let error = session.appsError {
                    Text(error).foregroundStyle(.secondary).padding()
                } else {
                    ProgressView().padding()
                }
            } else if filtered.isEmpty {
                Text("没有匹配的应用").foregroundStyle(.secondary).padding()
            }
        }
        .overlay(alignment: .bottom) { statusBar }
    }

    @ViewBuilder
    private var statusBar: some View {
        if session.phase == .startingMirror {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在连接…") }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(16)
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(16)
        }
    }

    private func open(_ app: PhoneApp) {
        guard !session.isBusy else { return }
        Task {
            await session.open(app)
            if session.isRunning { openWindow(id: WindowID.mirror) }
        }
    }
}
