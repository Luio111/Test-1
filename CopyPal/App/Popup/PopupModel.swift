import CoreGraphics
import Foundation
import Observation
import CopyPalCore

/// Which list the popup shows (⇥ switches).
enum PopupList: Equatable {
    case history
    case favorites
}

/// Short confirmation shown in the footer after ⌘P.
enum PopupNotice: Equatable {
    case favoriteAdded
    case favoriteRemoved
}

/// Fixed metrics, so the popup's size is known before SwiftUI lays it out.
enum PopupMetrics {
    /// Body width (without the flares at the top edge); wider on screens whose notch
    /// leaves less room beside it, see `minimumWing`.
    static let width: CGFloat = 520
    static let rowHeight: CGFloat = 28
    static let listHorizontalPadding: CGFloat = 8
    static let listVerticalPadding: CGFloat = 4
    static let emptyHeight: CGFloat = 56
    static let footerHeight: CGFloat = 26
    /// Search (left) and list switch (right) sit beside the notch, in its height.
    static let wingPadding: CGFloat = 16
    static let notchGap: CGFloat = 10
    static let minimumWing: CGFloat = 140
    static let bottomRadius: CGFloat = 20
    /// Concave corners where the shape meets the top edge, like the notch itself.
    static let flare: CGFloat = 8
    /// Room for the shadow beside and below the shape.
    static let shadowMargin: CGFloat = 24
    static let maxRows = PopupKeyMap.maxIndex

    static func listHeight(rows: Int) -> CGFloat {
        rows > 0 ? CGFloat(rows) * rowHeight + 2 * listVerticalPadding : emptyHeight
    }
}

/// Geometry of one appearance of the popup, in the panel's coordinates (origin top left).
struct PopupLayout: Equatable {
    /// The panel: the tallest popup plus room for the shadow. Fixed while it is open,
    /// so only the shape animates, never the window.
    var panelSize: CGSize
    /// The popup body for the current number of rows (without the flares).
    var bodySize: CGSize
    /// Height of the strip beside the notch (search and list switch).
    var bandHeight: CGFloat
    /// Space kept free for the camera housing (0 without notch).
    var notchGap: CGFloat
    /// Collapsed state: exactly the notch, so it is hidden behind the camera housing.
    /// Without notch a sliver at the top edge that then drops down.
    var startSize: CGSize

    static let zero = PopupLayout(panelSize: .zero, bodySize: .zero, bandHeight: 0, notchGap: 0, startSize: .zero)

    init(panelSize: CGSize, bodySize: CGSize, bandHeight: CGFloat, notchGap: CGFloat, startSize: CGSize) {
        self.panelSize = panelSize
        self.bodySize = bodySize
        self.bandHeight = bandHeight
        self.notchGap = notchGap
        self.startSize = startSize
    }

    init(anchor: NotchAnchor, rows: Int) {
        let notchGap = anchor.notchWidth > 0 ? anchor.notchWidth + 2 * PopupMetrics.notchGap : 0
        let width = max(PopupMetrics.width, notchGap + 2 * (PopupMetrics.minimumWing + PopupMetrics.wingPadding))
        func height(rows: Int) -> CGFloat {
            anchor.height + PopupMetrics.listHeight(rows: rows) + PopupMetrics.footerHeight
        }
        let margin = PopupMetrics.shadowMargin
        self.init(
            panelSize: CGSize(
                width: width + 2 * (PopupMetrics.flare + margin),
                height: height(rows: PopupMetrics.maxRows) + margin
            ),
            bodySize: CGSize(width: width, height: height(rows: rows)),
            bandHeight: anchor.height,
            notchGap: notchGap,
            startSize: anchor.notchWidth > 0
                ? CGSize(width: anchor.notchWidth, height: anchor.height)
                : CGSize(width: width * 0.6, height: 0)
        )
    }

    /// Width of the search and the list switch beside the notch.
    var wingWidth: CGFloat {
        max((bodySize.width - notchGap) / 2 - PopupMetrics.wingPadding, 0)
    }

    /// The black shape: the notch while collapsed, the popup when expanded.
    func silhouette(expanded: Bool) -> NotchShape {
        if expanded {
            return NotchShape(
                bodyWidth: bodySize.width,
                height: bodySize.height,
                bottomRadius: PopupMetrics.bottomRadius,
                flare: PopupMetrics.flare
            )
        }
        return NotchShape(
            bodyWidth: startSize.width,
            height: startSize.height,
            bottomRadius: min(10, startSize.height / 3),
            flare: 0
        )
    }
}

@MainActor
@Observable
final class PopupModel {
    var list: PopupList = .history
    var query = ""
    var selectedIndex = 0
    var layout = PopupLayout.zero
    /// false = the shape sits in the notch, true = the popup has dropped down.
    var expanded = false
    var contentVisible = false
    var notice: PopupNotice?

    @ObservationIgnored let history: HistoryModel
    @ObservationIgnored private let visuals: ClipVisuals
    @ObservationIgnored private let presentation: PresentationMode

    init(history: HistoryModel, visuals: ClipVisuals, presentation: PresentationMode) {
        self.history = history
        self.visuals = visuals
        self.presentation = presentation
    }

    /// Presentation mode: rows say what kind each entry is, never its content.
    var concealsContent: Bool {
        presentation.isActive
    }

    /// At most 8 entries: the search result in the current list.
    var visibleItems: [ClipItem] {
        let source = list == .history ? history.items : history.favorites
        let names = query.isEmpty ? [:] : visuals.appNames(for: source)
        return Array(HistorySearch.filter(source, query: query, appNames: names).prefix(PopupMetrics.maxRows))
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func reset() {
        list = .history
        query = ""
        selectedIndex = 0
        notice = nil
    }

    func clampSelection() {
        selectedIndex = min(max(selectedIndex, 0), max(visibleItems.count - 1, 0))
    }
}
