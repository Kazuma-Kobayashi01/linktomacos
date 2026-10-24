import Foundation
import LinkCore
import Observation

struct DayGroup: Identifiable {
    let day: Date
    var items: [MediaItem]
    var id: Date { day }
}

/// 某个相簿（或全部、仅视频）的分页列表，按天分组。
@MainActor
@Observable
final class MediaListModel {
    static let pageSize = 400

    private let remote: PhoneRemote
    private let album: Int64?
    private let kind: MediaKind

    private(set) var items: [MediaItem] = []
    private(set) var groups: [DayGroup] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var error: String?
    private var reachedEnd = false
    private var groupIndex: [Date: Int] = [:]
    private var itemIndex: [Int64: Int] = [:]

    init(remote: PhoneRemote, album: Int64?, kind: MediaKind) {
        self.remote = remote
        self.album = album
        self.kind = kind
    }

    var isEmpty: Bool { !isLoading && error == nil && items.isEmpty }

    func index(of id: Int64) -> Int? { itemIndex[id] }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await remote.media(album: album, kind: kind, offset: items.count, limit: Self.pageSize)
            total = page.total
            append(page.items)
            if page.items.isEmpty || items.count >= page.total { reachedEnd = true }
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 滚动到列表尾部附近时预取下一页。
    func loadMoreIfNeeded(at item: MediaItem) {
        guard let index = itemIndex[item.id], index >= items.count - 80 else { return }
        Task { await loadMore() }
    }

    func reload() async {
        items = []
        groups = []
        groupIndex = [:]
        itemIndex = [:]
        total = 0
        reachedEnd = false
        error = nil
        await loadMore()
    }

    private func append(_ page: [MediaItem]) {
        let calendar = Calendar.current
        for item in page {
            guard itemIndex[item.id] == nil else { continue }
            itemIndex[item.id] = items.count
            items.append(item)
            let day = calendar.startOfDay(for: item.dateValue)
            if let index = groupIndex[day] {
                groups[index].items.append(item)
            } else {
                groupIndex[day] = groups.count
                groups.append(DayGroup(day: day, items: [item]))
            }
        }
    }
}
