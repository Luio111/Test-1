import Foundation
import Observation
import CopyPalCore

/// Which list the popup shows (⇥ switches).
enum PopupList: Equatable {
    case history
    case favorites
}

/// Fixed metrics, so the popup's size is known before SwiftUI lays it out.
enum PopupMetrics {
    static let width: CGFloat = 420
    static let headerHeight: CGFloat = 46
    static let rowHeight: CGFloat = 34
    static let listPadding: CGFloat = 6
    static let emptyHeight: CGFloat = 76
    static let footerHeight: CGFloat = 32
    static let maxRows = PopupKeyMap.maxIndex

    static func cardHeight(rows: Int) -> CGFloat {
        let list = rows > 0 ? CGFloat(rows) * rowHeight + 2 * listPadding : emptyHeight
        return headerHeight + 1 + list + 1 + footerHeight
    }
}

/// Where the popup's grow animation starts (the notch, or a small capsule at the top)
/// and where the card ends up, in the panel's coordinates (origin top left).
struct PopupLayout: Equatable {
    var panelSize: CGSize
    var cardTop: CGFloat
    var cardSize: CGSize
    var startSize: CGSize
    var startTop: CGFloat
    var startRadius: CGFloat

    static let zero = PopupLayout(panelSize: .zero, cardTop: 0, cardSize: .zero, startSize: .zero, startTop: 0, startRadius: 0)
}

@MainActor
@Observable
final class PopupModel {
    var list: PopupList = .history
    var query = ""
    var selectedIndex = 0
    var layout = PopupLayout.zero
    /// Grow animation: false = shape at the notch, true = full card.
    var expanded = false
    var contentVisible = false

    @ObservationIgnored let history: HistoryModel

    init(history: HistoryModel) {
        self.history = history
    }

    /// At most 8 entries: the search result in the current list.
    var visibleItems: [ClipItem] {
        let source = list == .history ? history.items : history.favorites
        return Array(HistorySearch.filter(source, query: query).prefix(PopupMetrics.maxRows))
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func reset() {
        list = .history
        query = ""
        selectedIndex = 0
    }

    func clampSelection() {
        selectedIndex = min(max(selectedIndex, 0), max(visibleItems.count - 1, 0))
    }
}
