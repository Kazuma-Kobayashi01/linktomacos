import SwiftUI
import WidgetKit

/// 手机状态小组件：电量、存储、内存、网络，大号还有 24 小时电量曲线。点一下打开 Link to macOS 的概览页。
struct LinkTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LinkWidgetEntry {
        LinkWidgetEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LinkWidgetEntry) -> Void) {
        // 图库预览里用示例数据，看起来更完整
        completion(LinkWidgetEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LinkWidgetEntry>) -> Void) {
        let entry = LinkWidgetEntry(date: Date(), snapshot: WidgetSnapshot.read())
        // 主程序有新数据时会主动刷新；这里的定时刷新只是兜底，也让“几分钟前”保持准确
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct LinkStatusWidget: Widget {
    let kind = "LinkStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LinkTimelineProvider()) { entry in
            LinkWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("手机状态")
        .description("在桌面上看手机的电量、存储、内存和网络。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct LinkWidgetBundle: WidgetBundle {
    var body: some Widget {
        LinkStatusWidget()
    }
}
