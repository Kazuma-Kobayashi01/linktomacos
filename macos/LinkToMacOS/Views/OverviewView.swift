import Charts
import LinkCore
import SwiftUI

/// 默认启动页：设备信息、实时状态、历史曲线和明细表。手机离线时显示最后已知的数据。
struct OverviewView: View {
    let monitor: DeviceMonitor
    @Environment(AppModel.self) private var model
    @State private var range: HistoryRange = .sixHours
    @State private var confirmingUnpair = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 12) {
                    if !monitor.isOnline { OfflineBanner(lastSeen: monitor.lastSeen) }
                    HeroCard(monitor: monitor, onRefresh: refresh, onUnpair: { confirmingUnpair = true })
                }

                Section {
                    Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            BatteryTile(status: monitor.status)
                            StorageTile(storage: monitor.storage)
                        }
                        GridRow {
                            MemoryTile(status: monitor.status, info: monitor.info)
                            NetworkTile(status: monitor.status)
                        }
                    }
                } header: {
                    SectionHeader("状态")
                }

                Section {
                    HistoryCard(history: monitor.history, range: $range)
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader("历史")
                        Spacer()
                        Picker("范围", selection: $range) {
                            ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                Section {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            DeviceInfoCard(monitor: monitor, onUnpair: { confirmingUnpair = true })
                                .frame(minWidth: 360, maxWidth: .infinity)
                            StorageCard(storage: monitor.storage).frame(width: 360)
                        }
                        VStack(spacing: 16) {
                            DeviceInfoCard(monitor: monitor, onUnpair: { confirmingUnpair = true })
                            StorageCard(storage: monitor.storage)
                        }
                    }
                } header: {
                    SectionHeader("详细信息")
                }
            }
            .padding(24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("概览")
        .navigationSubtitle(monitor.name)
        .toolbar {
            Button(action: refresh) { Label("刷新", systemImage: "arrow.clockwise") }
                .help("刷新设备信息（⌘R）")
                .keyboardShortcut("r")
                .disabled(!monitor.isOnline)
        }
        .confirmationDialog(
            Text("取消与“\(monitor.name)”的配对？"),
            isPresented: $confirmingUnpair
        ) {
            Button("取消配对", role: .destructive, action: unpair)
            Button("取消", role: .cancel) {}
        } message: {
            Text("取消后，这台手机需要重新扫码才能连接。Mac 上保存的这台手机的设备信息和历史记录也会删除。")
        }
    }

    private func refresh() {
        Task {
            await monitor.refreshInfo()
            await monitor.refreshStorage()
        }
    }

    private func unpair() {
        guard let device = model.pairedDevices.first(where: { $0.deviceId == monitor.id }) else { return }
        model.unpair(device)
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case oneHour, sixHours, day
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .sixHours: 6 * 3600
        case .day: 24 * 3600
        }
    }
    var title: LocalizedStringKey {
        switch self {
        case .oneHour: "1 小时"
        case .sixHours: "6 小时"
        case .day: "24 小时"
        }
    }
}

// MARK: - 外观

private enum Palette {
    static let battery = Color.green
    static let storage = Color.blue
    static let memory = Color.purple
    static let network = Color.orange
    static let temperature = Color.orange
    static let signal = Color.blue
}

private struct SectionHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title).font(.title3.weight(.semibold))
    }
}

/// 卡片底板：浅色背景、细边框、柔和阴影，深浅色模式都协调。
private struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            }
    }
}

private extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// 彩色圆角图标，和系统设置里的风格一致。
private struct IconBadge: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.26, style: .continuous))
    }
}

private struct TileHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(systemImage: systemImage, tint: tint)
            Text(title).font(.headline)
            Spacer()
        }
    }
}

private struct Pill: View {
    let systemImage: String?
    let text: String
    var tint: Color = .secondary
    var dot: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            } else if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text).lineLimit(1)
        }
        .font(.callout)
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - 顶部：设备

private struct OfflineBanner: View {
    let lastSeen: Date?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").foregroundStyle(.orange)
            if let lastSeen {
                Text("手机已离线，以下是最后一次连接时的数据（\(lastSeen.formatted(.relative(presentation: .named)))）")
            } else {
                Text("手机尚未连接过，连接后这里会显示设备信息和状态")
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.5) }
    }
}

/// 手机插图：深色机身、渐变屏幕、打孔摄像头，在线时屏幕亮起。
private struct PhoneGlyph: View {
    let online: Bool
    let battery: Int?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(screen)
                .padding(4)
            VStack {
                Circle().fill(Color.black.opacity(0.85)).frame(width: 6, height: 6).padding(.top, 9)
                Spacer()
                if online, let battery {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").imageScale(.small)
                        Text("\(battery)%").monospacedDigit()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(width: 66, height: 132)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private var screen: LinearGradient {
        online
            ? LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1.0), Color(red: 0.62, green: 0.35, blue: 0.95)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(white: 0.22), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
    }
}

private struct HeroCard: View {
    let monitor: DeviceMonitor
    let onRefresh: () -> Void
    let onUnpair: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            PhoneGlyph(online: monitor.isOnline, battery: monitor.status?.batteryLevel)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.name).font(.system(size: 26, weight: .bold)).lineLimit(1)
                    Text(subtitle).font(.title3).foregroundStyle(.secondary).lineLimit(1)
                }

                HStack(spacing: 8) {
                    if monitor.isOnline {
                        Pill(systemImage: nil, text: String(localized: "已连接"), tint: .green, dot: .green)
                        if let address = monitor.address {
                            Pill(systemImage: "network", text: address)
                        }
                        if let since = monitor.connectedSince {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Pill(systemImage: "link", text: Format.duration(context.date.timeIntervalSince(since)))
                            }
                        }
                    } else {
                        Pill(systemImage: nil, text: String(localized: "离线"), dot: .gray)
                    }
                    if monitor.isOnline, let uptime = monitor.status?.uptime {
                        Pill(systemImage: "power", text: String(localized: "开机 \(Format.duration(TimeInterval(uptime) / 1000))"))
                    }
                }

                if let info = monitor.info {
                    ChipRow(info: info)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button("刷新设备信息", systemImage: "arrow.clockwise", action: onRefresh)
                    .disabled(!monitor.isOnline)
                Divider()
                Button("取消配对…", systemImage: "link.badge.minus", role: .destructive, action: onUnpair)
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(monitor.isOnline ? 0.16 : 0.06), .clear],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        }
    }

    private var subtitle: String {
        if let info = monitor.info {
            return "\(info.manufacturer.capitalized) \(info.model) · Android \(info.androidVersion)"
        }
        return monitor.model
    }
}

/// 处理器：品牌色徽标 + 完整名称，下面一行是厂商、核心数和架构。
private struct ChipRow: View {
    let info: DeviceInfo

    var body: some View {
        HStack(spacing: 10) {
            if let chip = ChipCatalog.lookup(info) {
                ChipBadge(vendor: chip.vendor, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chip.name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(detail(chip)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                ChipBadge(vendor: .other, size: 28)
                Text(detail(nil)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func detail(_ chip: ChipInfo?) -> String {
        var parts: [String] = []
        if let vendor = chip?.vendor.displayName, !vendor.isEmpty { parts.append(vendor) }
        parts.append(String(localized: "\(info.cpuCores) 核"))
        parts.append(info.abi)
        return parts.joined(separator: " · ")
    }
}

// MARK: - 状态卡片

/// 渐变圆环，中间放主要数值。
private struct Ring<Center: View>: View {
    let fraction: Double
    let tint: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(1, fraction)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: 92, height: 92)
    }
}

private struct Line: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.75)
        }
        .font(.callout)
    }
}

private struct BigValue: View {
    let value: String
    let caption: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            if let caption { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 6)
    }
}

private struct EmptyTileBody: View {
    var body: some View {
        Text("暂无数据").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 92)
    }
}

private struct BatteryTile: View {
    let status: DeviceStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TileHeader(title: "电池", systemImage: status?.charging == true ? "battery.100percent.bolt" : "battery.75percent", tint: Palette.battery)
            if let status {
                HStack(spacing: 18) {
                    Ring(fraction: Double(status.batteryLevel) / 100, tint: tint(status)) {
                        VStack(spacing: 0) {
                            BigValue(value: "\(status.batteryLevel)%", caption: nil)
                            if status.charging {
                                Image(systemName: "bolt.fill").font(.caption).foregroundStyle(Palette.battery)
                            }
                        }
                    }
                    VStack(spacing: 7) {
                        Line(label: "状态", value: stateText(status))
                        Line(label: "温度", value: status.batteryTemperature.map { String(format: "%.1f °C", $0) } ?? "—")
                        Line(label: "电压", value: status.batteryVoltage.map { String(format: "%.2f V", Double($0) / 1000) } ?? "—")
                        Line(label: "健康", value: Format.health(status.batteryHealth))
                    }
                }
            } else {
                EmptyTileBody()
            }
        }
        .card()
    }

    private func tint(_ status: DeviceStatus) -> Color {
        if status.charging { return Palette.battery }
        return status.batteryLevel <= 20 ? .red : (status.batteryLevel <= 40 ? .orange : Palette.battery)
    }

    private func stateText(_ status: DeviceStatus) -> String {
        guard status.charging else { return String(localized: "未充电") }
        return String(localized: "充电中 · \(Format.chargingType(status.chargingType))")
    }
}

private struct StorageSegment: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let bytes: Int64
    let color: Color
}

private func segments(for storage: StorageBreakdown) -> [StorageSegment] {
    [
        StorageSegment(id: "images", title: "图片", bytes: storage.images, color: .blue),
        StorageSegment(id: "videos", title: "视频", bytes: storage.videos, color: .purple),
        StorageSegment(id: "audio", title: "音频", bytes: storage.audio, color: .pink),
        StorageSegment(id: "other", title: "其他", bytes: storage.other, color: .orange),
        StorageSegment(id: "free", title: "可用", bytes: storage.free, color: Color.secondary.opacity(0.22)),
    ]
}

private struct StorageTile: View {
    let storage: StorageBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TileHeader(title: "存储", systemImage: "internaldrive.fill", tint: Palette.storage)
            if let storage, storage.total > 0 {
                HStack(spacing: 18) {
                    Chart(segments(for: storage).filter { $0.bytes > 0 }) { segment in
                        SectorMark(angle: .value("大小", segment.bytes), innerRadius: .ratio(0.72), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(segment.color)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 92, height: 92)
                    .overlay {
                        BigValue(value: "\(Int((Double(storage.used) / Double(storage.total) * 100).rounded()))%", caption: "已用")
                    }
                    VStack(spacing: 7) {
                        Line(label: "已用", value: Format.bytes(storage.used))
                        Line(label: "可用", value: Format.bytes(storage.free))
                        Line(label: "总容量", value: Format.bytes(storage.total))
                    }
                }
            } else {
                EmptyTileBody()
            }
        }
        .card()
    }
}

private struct MemoryTile: View {
    let status: DeviceStatus?
    let info: DeviceInfo?

    private var total: Int64? { status?.memoryTotal ?? info?.memoryTotal }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TileHeader(title: "内存", systemImage: "memorychip.fill", tint: Palette.memory)
            if let total, total > 0, let available = status?.memoryAvailable {
                let used = max(0, total - available)
                let fraction = Double(used) / Double(total)
                HStack(spacing: 18) {
                    Ring(fraction: fraction, tint: fraction > 0.85 ? .red : Palette.memory) {
                        BigValue(value: "\(Int((fraction * 100).rounded()))%", caption: "已用")
                    }
                    VStack(spacing: 7) {
                        Line(label: "已用", value: Format.memory(used))
                        Line(label: "可用", value: Format.memory(available))
                        Line(label: "总容量", value: Format.memory(total))
                    }
                }
            } else {
                EmptyTileBody()
            }
        }
        .card()
    }
}

private struct NetworkTile: View {
    let status: DeviceStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TileHeader(title: "网络", systemImage: "antenna.radiowaves.left.and.right", tint: Palette.network)
            if let status {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Palette.network.opacity(0.12))
                        VStack(spacing: 4) {
                            if status.wifiConnected {
                                Image(systemName: "wifi", variableValue: Double(status.wifiLevel ?? 4) / 4)
                                    .font(.system(size: 30, weight: .semibold))
                            } else {
                                Image(systemName: "cellularbars", variableValue: Double(status.signalLevel ?? 0) / 4)
                                    .font(.system(size: 30, weight: .semibold))
                            }
                            Text(status.wifiConnected ? "Wi‑Fi" : (status.networkType ?? String(localized: "无网络")))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Palette.network)
                    }
                    .frame(width: 92, height: 92)
                    VStack(spacing: 7) {
                        Line(label: "连接方式", value: status.wifiConnected ? "Wi‑Fi" : (status.networkType ?? "—"))
                        if status.wifiConnected {
                            Line(label: "连接速率", value: status.wifiLinkSpeed.map { "\($0) Mbps" } ?? "—")
                        }
                        Line(label: "运营商", value: status.carrier ?? "—")
                        Line(label: "蜂窝信号", value: status.signalDbm.map { "\($0) dBm" } ?? status.signalLevel.map { "\($0)/4" } ?? "—")
                    }
                }
            } else {
                EmptyTileBody()
            }
        }
        .card()
    }
}

// MARK: - 历史曲线

private struct HistoryCard: View {
    let history: [HistoryPoint]
    @Binding var range: HistoryRange

    private var visible: [HistoryPoint] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        return history.filter { $0.time >= cutoff }
    }

    var body: some View {
        let points = visible
        Group {
            if points.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("数据不足。保持连接一段时间后，这里会显示电量、温度和信号的变化。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    BatteryChart(points: points)
                    if points.contains(where: { $0.temperature != nil }) {
                        Divider()
                        TemperatureChart(points: points)
                    }
                    if points.contains(where: { $0.signalDbm != nil }) {
                        Divider()
                        SignalChart(points: points)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

private struct ChartTitle: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            IconBadge(systemImage: systemImage, tint: tint, size: 22)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct BatteryChart: View {
    let points: [HistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChartTitle(title: "电量", systemImage: "battery.75percent", tint: Palette.battery, value: points.last.map { "\($0.battery)%" } ?? "")
            Chart(points) { point in
                AreaMark(x: .value("时间", point.time), y: .value("电量", point.battery))
                    .foregroundStyle(.linearGradient(colors: [Palette.battery.opacity(0.32), Palette.battery.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("时间", point.time), y: .value("电量", point.battery))
                    .foregroundStyle(Palette.battery)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { AxisGridLine(); AxisValueLabel("\($0.as(Int.self) ?? 0)%") } }
            .frame(height: 140)
        }
    }
}

private struct TemperatureChart: View {
    let points: [HistoryPoint]

    var body: some View {
        let temps = points.compactMap { p in p.temperature.map { (p.time, $0) } }
        VStack(alignment: .leading, spacing: 10) {
            ChartTitle(title: "电池温度", systemImage: "thermometer.medium", tint: Palette.temperature,
                       value: temps.last.map { String(format: "%.1f °C", $0.1) } ?? "")
            Chart(temps, id: \.0) { time, value in
                AreaMark(x: .value("时间", time), yStart: .value("温度", (temps.map(\.1).min() ?? value) - 1), yEnd: .value("温度", value))
                    .foregroundStyle(.linearGradient(colors: [Palette.temperature.opacity(0.28), Palette.temperature.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("时间", time), y: .value("温度", value))
                    .foregroundStyle(Palette.temperature)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 120)
        }
    }
}

private struct SignalChart: View {
    let points: [HistoryPoint]

    var body: some View {
        let signals = points.compactMap { p in p.signalDbm.map { (p.time, $0) } }
        VStack(alignment: .leading, spacing: 10) {
            ChartTitle(title: "蜂窝信号", systemImage: "cellularbars", tint: Palette.signal, value: signals.last.map { "\($0.1) dBm" } ?? "")
            Chart(signals, id: \.0) { time, value in
                AreaMark(x: .value("时间", time), yStart: .value("信号", -130), yEnd: .value("信号", value))
                    .foregroundStyle(.linearGradient(colors: [Palette.signal.opacity(0.25), Palette.signal.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("时间", time), y: .value("信号", value))
                    .foregroundStyle(Palette.signal)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.stepEnd)
            }
            .chartYScale(domain: -130 ... -50)
            .frame(height: 120)
        }
    }
}

// MARK: - 明细

private struct InfoRow: View {
    let systemImage: String
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 12)
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
        .padding(.vertical, 8)
    }
}

private struct DeviceInfoCard: View {
    let monitor: DeviceMonitor
    let onUnpair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileHeader(title: "设备信息", systemImage: "info", tint: .gray)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, 28) }
                    InfoRow(systemImage: row.0, label: row.1, value: row.2)
                }
            }
            Divider()
            HStack {
                Text("不再连接这台手机").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onUnpair) {
                    Label("取消配对…", systemImage: "link.badge.minus").foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .card()
    }

    private var rows: [(String, LocalizedStringKey, String)] {
        var rows: [(String, LocalizedStringKey, String)] = [
            ("iphone", "设备名称", monitor.name),
            ("number", "型号", monitor.model),
        ]
        if let info = monitor.info {
            let chip = ChipCatalog.lookup(info)?.name ?? info.abi
            rows += [
                ("building.2", "制造商", info.manufacturer.capitalized),
                ("gearshape", "系统版本", "Android \(info.androidVersion) (API \(info.sdk))"),
                ("lock.shield", "安全补丁", info.securityPatch),
                ("hammer", "系统构建", info.buildId),
                ("cpu", "处理器", "\(chip)\n\(info.abi) · \(String(localized: "\(info.cpuCores) 核"))"),
                ("memorychip", "内存", Format.memory(info.memoryTotal)),
                ("rectangle.portrait", "屏幕", "\(info.screenWidth) × \(info.screenHeight) · \(info.densityDpi) dpi · \(Int(info.refreshRate.rounded())) Hz"),
                ("globe", "语言", Format.language(info.language)),
                ("clock", "时区", Format.timeZone(info.timezone)),
                ("app.badge", "LinkToMacOS 版本", info.appVersion),
            ]
        }
        if let pairedAt = monitor.pairedAt {
            rows.append(("link", "配对时间", pairedAt.formatted(date: .abbreviated, time: .shortened)))
        }
        return rows
    }
}

/// 存储明细：和访达“储存空间”一样的横向容量条，加图例。
private struct StorageCard: View {
    let storage: StorageBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TileHeader(title: "存储明细", systemImage: "chart.bar.fill", tint: Palette.storage)
            if let storage, storage.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.bytes(storage.used)).font(.title2.weight(.semibold)).monospacedDigit()
                        Text("已用，共 \(Format.bytes(storage.total))").foregroundStyle(.secondary)
                    }
                    CapacityBar(segments: segments(for: storage), total: storage.total)
                }

                VStack(spacing: 0) {
                    ForEach(segments(for: storage)) { segment in
                        HStack(spacing: 10) {
                            Circle().fill(segment.color).frame(width: 10, height: 10)
                            Text(segment.title).lineLimit(1)
                            Spacer()
                            Text(Format.bytes(segment.bytes)).monospacedDigit()
                            Text(String(format: "%.1f%%", Double(segment.bytes) / Double(storage.total) * 100))
                                .monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                        .font(.callout)
                        .padding(.vertical, 7)
                        if segment.id != "free" { Divider().padding(.leading, 20) }
                    }
                }

                if !storage.hasMedia {
                    Label("手机未授予相册读取权限，图片、视频、音频的占用暂时无法统计。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("暂无数据").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .card()
    }
}

private struct CapacityBar: View {
    let segments: [StorageSegment]
    let total: Int64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments.filter { $0.bytes > 0 }) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(2, proxy.size.width * CGFloat(segment.bytes) / CGFloat(total) - 2))
                }
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - 格式化

enum Format {
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    static func memory(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .memory) }

    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 86400 ? [.day, .hour] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(60, seconds)) ?? ""
    }

    /// “en-US-u-fw-mon…” → “English (United States)”，随界面语言显示。
    static func language(_ tag: String) -> String {
        let base = tag.components(separatedBy: "-u-").first ?? tag
        return Locale.current.localizedString(forIdentifier: base) ?? base
    }

    static func timeZone(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        return zone.localizedName(for: .standard, locale: .current) ?? identifier
    }

    static func health(_ value: String?) -> String {
        switch value {
        case "good": String(localized: "良好")
        case "overheat": String(localized: "过热")
        case "dead": String(localized: "已损坏")
        case "over_voltage": String(localized: "电压过高")
        case "cold": String(localized: "过冷")
        case "failure": String(localized: "故障")
        case .some: String(localized: "未知")
        case nil: "—"
        }
    }

    static func chargingType(_ value: String?) -> String {
        switch value {
        case "ac": String(localized: "充电器")
        case "usb": String(localized: "USB")
        case "wireless": String(localized: "无线充电")
        case "dock": String(localized: "底座")
        default: String(localized: "充电中")
        }
    }
}
