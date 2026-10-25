import LinkCore
import SwiftUI

/// 手机应用网格：搜索，点一下打开。用于开始投屏时选应用（弹窗），和投屏窗口里随时再开别的应用（浮层）。
struct AppLauncherView: View {
    let session: MirrorSession
    var showsStartWithoutApp = false
    let onPick: (PhoneApp) -> Void
    var onStartEmpty: (() -> Void)?

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [PhoneApp] {
        query.isEmpty ? session.apps : session.apps.filter {
            $0.label.localizedCaseInsensitiveContains(query) || $0.package.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("搜索应用", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 8)], spacing: 10) {
                    ForEach(filtered) { app in
                        AppCell(app: app, icons: session.icons)
                            .onTapGesture { onPick(app) }
                    }
                }
                .padding(.vertical, 4)
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
            Toggle("先结束应用再打开", isOn: Binding(get: { session.forceStopOnLaunch }, set: { session.forceStopOnLaunch = $0 }))
                .toggleStyle(.checkbox)
                .help("应用已经在手机屏幕上打开时需要勾选，否则系统会直接把那个窗口调到前面，而不是开在这里。会丢失该应用未保存的状态。")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsStartWithoutApp, let onStartEmpty {
                Button("不打开应用，直接开始", action: onStartEmpty)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(14)
        .task {
            await session.loadApps()
            searchFocused = true
        }
    }
}

/// 应用网格里的一格：图标和名称。
struct AppCell: View {
    let app: PhoneApp
    let icons: AppIconLoader
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(.quaternary)
                }
            }
            .frame(width: 52, height: 52)
            Text(app.label).font(.caption).lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .contentShape(Rectangle())
        .task(id: app.package) {
            icon = icons.cached(app.package)
            if icon == nil { icon = await icons.image(for: app.package) }
        }
    }
}
