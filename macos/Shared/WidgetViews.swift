import Charts
import SwiftUI
import WidgetKit

/// 桌面小组件的界面。主程序（调试时离屏渲染截图）和小组件扩展共用这一份。
struct LinkWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct LinkWidgetView: View {
    let entry: LinkWidgetEntry
    /// 离屏渲染截图时指定尺寸；小组件里留空，用系统给的。
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var snapshot: WidgetSnapshot { entry.snapshot ?? .sample }
    private var isPlaceholder: Bool { entry.snapshot == nil }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                EmptyState()
            } else {
                switch family {
                case .systemSmall: SmallView(snapshot: snapshot)
                case .systemMedium: MediumView(snapshot: snapshot)
                default: LargeView(snapshot: snapshot)
                }
            }
        }
        .widgetURL(URL(string: "linktomacos://overview"))
    }
}

// MARK: 小

private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        // 圆环贴着顶部，设备名和状态在下面；手机图标和在线点放在左上、右上的空角里
        VStack(spacing: 0) {
            BatteryRing(level: snapshot.battery, charging: snapshot.charging, dimmed: !snapshot.online)
                .frame(width: 78, height: 78)
                .padding(.top, 2)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.deviceName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                StatusLine(snapshot: snapshot).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topLeading) {
            Image(systemName: snapshot.online ? "iphone" : "iphone.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .overlay(alignment: .topTrailing) {
            StatusDot(online: snapshot.online).padding(.top, 4)
        }
    }
}

// MARK: 中

private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 6) {
                BatteryRing(level: snapshot.battery, charging: snapshot.charging, dimmed: !snapshot.online)
                    .frame(width: 80, height: 80)
                VStack(spacing: 1) {
                    Text(snapshot.deviceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    StatusLine(snapshot: snapshot).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .frame(width: 118)
            // 三行等距，和左边的圆环一样高，上下对齐
            VStack(spacing: 0) {
                Meter(title: "存储", used: snapshot.storageUsed, total: snapshot.storageTotal, tint: .blue)
                Spacer(minLength: 8)
                Meter(title: "内存", used: snapshot.memoryUsed, total: snapshot.memoryTotal, tint: .purple)
                Spacer(minLength: 8)
                NetworkRow(snapshot: snapshot)
            }
            .frame(maxHeight: 96)
        }
    }
}

// MARK: 大

private struct LargeView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MediumView(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 6) {
                Text("最近 24 小时电量").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if snapshot.history.count > 1 {
                    Chart(snapshot.history, id: \.time) { point in
                        AreaMark(x: .value("时间", point.time), y: .value("电量", point.battery))
                            .foregroundStyle(.linearGradient(colors: [.green.opacity(0.45), .green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("时间", point.time), y: .value("电量", point.battery))
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel { if let v = value.as(Int.self) { Text("\(v)%") } }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour())
                        }
                    }
                } else {
                    Text("数据不足").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: 零件

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("还没有连接过手机").font(.headline)
            Text("打开 Link to macOS 配对后，这里会显示手机的状态。").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StatusDot: View {
    let online: Bool
    var body: some View {
        Circle().fill(online ? Color.green : Color.gray.opacity(0.6)).frame(width: 8, height: 8)
    }
}

private struct StatusLine: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        if snapshot.online {
            Text(snapshot.charging ? "充电中" : "已连接")
        } else if let lastSeen = snapshot.lastSeen {
            Text("离线 · \(lastSeen.formatted(.relative(presentation: .named)))")
        } else {
            Text("离线")
        }
    }
}

/// 圆环电量，中间是百分比，充电时有闪电。
struct BatteryRing: View {
    let level: Int?
    let charging: Bool
    var dimmed = false

    private var fraction: Double { Double(level ?? 0) / 100 }
    private var tint: Color {
        guard let level else { return .gray }
        if charging { return .green }
        return level <= 10 ? .red : level <= 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 9)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if charging { Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(tint) }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(level.map { "\($0)" } ?? "–")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    if level != nil {
                        Text("%").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
                .minimumScaleFactor(0.6)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct Meter: View {
    let title: LocalizedStringKey
    let used: Int64?
    let total: Int64?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let used, let total {
                    Text("\(ByteCountFormatter.string(fromByteCount: used, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint.gradient).frame(width: max(6, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
    }

    private var fraction: Double {
        guard let used, let total, total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }
}

private struct NetworkRow: View {
    let snapshot: WidgetSnapshot

    private var isWiFi: Bool { snapshot.network == "Wi‑Fi" }

    var body: some View {
        // 和存储、内存两行一样：标题在左，数值在右
        HStack {
            Text("网络").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 5) {
                Text(snapshot.network ?? "–").font(.caption2).foregroundStyle(.secondary)
                if let level = snapshot.signalLevel {
                    Image(systemName: isWiFi ? "wifi" : "cellularbars", variableValue: Double(level) / 4)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}
