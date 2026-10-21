import AppKit
import SwiftUI
import CopyPalCore

/// "Verlauf öffnen": the whole history and the favorites in a calm, Notion-like page.
/// Copy, pin, rename, reorder favorites, reveal or un-mark sensitive entries, delete.
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private let history: HistoryModel
    private let visuals: ClipVisuals
    private let paster: PasteController
    private let onClearHistory: () -> Void
    private var window: NSWindow?

    init(history: HistoryModel, visuals: ClipVisuals, paster: PasteController, onClearHistory: @escaping () -> Void) {
        self.history = history
        self.visuals = visuals
        self.paster = paster
        self.onClearHistory = onClearHistory
    }

    func show(list: PopupList = .history) {
        let window = window ?? makeWindow(list: list)
        self.window = window
        Task { await history.reload() }
        FocusReturn.remember()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        FocusReturn.windowWillClose(window)
    }

    private func makeWindow(list: PopupList) -> NSWindow {
        let view = HistoryPage(history: history, visuals: visuals, paster: paster, initialList: list, onClearHistory: onClearHistory)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = String(localized: "Verlauf")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.Colors.windowBackground
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(width: 680, height: 720))
        window.setFrameAutosaveName("CopyPal.History")
        window.center()
        window.delegate = self
        return window
    }
}

private struct HistoryPage: View {
    let history: HistoryModel
    let visuals: ClipVisuals
    let paster: PasteController
    let onClearHistory: () -> Void

    @State private var list: PopupList
    @State private var query = ""
    @State private var revealed: [UUID: String] = [:]
    @State private var renaming: ClipItem?
    @State private var newLabel = ""

    init(history: HistoryModel, visuals: ClipVisuals, paster: PasteController, initialList: PopupList, onClearHistory: @escaping () -> Void) {
        self.history = history
        self.visuals = visuals
        self.paster = paster
        self.onClearHistory = onClearHistory
        _list = State(initialValue: initialList)
    }

    private var items: [ClipItem] {
        let source = list == .history ? history.items : history.favorites
        let names = query.isEmpty ? [:] : visuals.appNames(for: source)
        return HistorySearch.filter(source, query: query, appNames: names)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header
            controls
            Hairline()
            if items.isEmpty {
                emptyState
            } else {
                entryList
            }
            footer
        }
        .padding(.horizontal, Theme.Layout.pageHorizontalPadding)
        .padding(.top, Theme.Layout.pageTopPadding)
        .padding(.bottom, Theme.Spacing.l)
        .frame(minWidth: 520, minHeight: 480)
        .background(Theme.Colors.background)
        .alert("Favorit benennen", isPresented: isRenaming) {
            TextField("Name, z. B. „E-Mail privat“", text: $newLabel)
            Button("Sichern", action: saveLabel)
            Button("Abbrechen", role: .cancel) { renaming = nil }
        }
    }

    private var entryList: some View {
        List {
            ForEach(items) { item in
                row(for: item)
            }
            .onMove(perform: moveAction)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(for item: ClipItem) -> some View {
        HistoryRow(item: item, visuals: visuals, revealedText: revealed[item.id], actions: actions(for: item))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
    }

    /// Favorites can be reordered by dragging, but only the full, unfiltered list.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard list == .favorites, query.isEmpty else { return nil }
        return { source, destination in
            moveFavorites(from: source, to: destination)
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { presented in
            if !presented { renaming = nil }
        })
    }

    private func saveLabel() {
        defer { renaming = nil }
        guard let id = renaming?.id else { return }
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        let value: String? = label.isEmpty ? nil : label
        Task { await history.perform { try await $0.setPinLabel(id, label: value) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
            Text("Verlauf")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Alles bleibt verschlüsselt auf diesem Mac. Sensible Einträge sind verdeckt und verschwinden nach kurzer Zeit.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                TextField("Suchen", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 28)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control))

            Picker("Liste", selection: $list) {
                Text("Verlauf").tag(PopupList.history)
                Text("Favoriten").tag(PopupList.favorites)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(emptyTitle)
                .font(Theme.Typography.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            if query.isEmpty, list == .favorites {
                Text("Mit ⌘P im Pop-up oder über das Menü eines Eintrags.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: LocalizedStringKey {
        if !query.isEmpty { return "Keine Treffer" }
        return list == .history ? "Noch nichts kopiert" : "Noch keine Favoriten"
    }

    private var footer: some View {
        HStack {
            Text("\(history.items.count) Einträge · \(history.favorites.count) Favoriten")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Button("Verlauf löschen …", action: onClearHistory)
                .buttonStyle(SubtleButtonStyle())
        }
    }

    private func moveFavorites(from source: IndexSet, to destination: Int) {
        var ids = history.favorites.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let ordered = ids
        Task { await history.perform { try await $0.reorderFavorites(ordered) } }
    }

    private func actions(for item: ClipItem) -> HistoryRow.Actions {
        let id = item.id
        return HistoryRow.Actions(
            copy: { Task { await paster.copy(item) } },
            copyPlain: { Task { await paster.copy(item, plainText: true) } },
            togglePin: { Task { await history.perform { try await $0.togglePin(id) } } },
            rename: item.isPinned ? {
                newLabel = item.pinLabel ?? ""
                renaming = item
            } : nil,
            reveal: item.isSensitive ? { reveal(item) } : nil,
            markNotSensitive: item.isSensitive ? {
                Task { await history.perform { try await $0.clearSensitivity(id) } }
            } : nil,
            delete: { Task { await history.perform { try await $0.delete([id]) } } }
        )
    }

    /// Shows a sensitive entry's text for 10 seconds (ROADMAP M5: only on request).
    private func reveal(_ item: ClipItem) {
        if revealed[item.id] != nil {
            revealed[item.id] = nil
            return
        }
        let id = item.id
        Task {
            let representations = (try? await history.engine.representations(of: id)) ?? []
            let text = representations.first { $0.type == PasteboardTypeID.plainText }
                .flatMap { String(data: $0.data, encoding: .utf8) }
            revealed[id] = text.map { TextFolding.firstLine(of: $0, maxLength: 120) } ?? ""
            try? await Task.sleep(for: .seconds(10))
            revealed[id] = nil
        }
    }
}

private struct HistoryRow: View {
    struct Actions {
        var copy: () -> Void
        var copyPlain: () -> Void
        var togglePin: () -> Void
        var rename: (() -> Void)?
        var reveal: (() -> Void)?
        var markNotSensitive: (() -> Void)?
        var delete: () -> Void
    }

    let item: ClipItem
    let visuals: ClipVisuals
    let revealedText: String?
    let actions: Actions
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ClipLeadingVisual(item: item, visuals: visuals, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                if let label = item.pinLabel {
                    Text(verbatim: label)
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                HStack(spacing: Theme.Spacing.s) {
                    Text(verbatim: revealedText ?? visuals.title(for: item))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    ClipTags(item: item, visuals: visuals)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            if isHovering {
                hoverButtons
            }
            ClipTrailingDetails(item: item, visuals: visuals)
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.s - 2)
        .background(isHovering ? Theme.Colors.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: actions.copy)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Kopieren"), actions.copy)
        .accessibilityAction(named: Text(pinTitle), actions.togglePin)
        .accessibilityAction(named: Text("Löschen"), actions.delete)
    }

    private var pinTitle: LocalizedStringKey {
        item.isPinned ? "Aus Favoriten entfernen" : "Zu Favoriten"
    }

    private var hoverButtons: some View {
        HStack(spacing: 2) {
            iconButton("doc.on.doc", help: "Kopieren", action: actions.copy)
            iconButton(item.isPinned ? "pin.slash" : "pin", help: pinTitle, action: actions.togglePin)
            if let reveal = actions.reveal {
                iconButton(revealedText == nil ? "eye" : "eye.slash", help: "Anzeigen", action: reveal)
            }
            iconButton("trash", help: "Löschen", action: actions.delete)
        }
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.Colors.textSecondary)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Kopieren", action: actions.copy)
        Button("Als reinen Text kopieren", action: actions.copyPlain)
        Divider()
        Button(pinTitle, action: actions.togglePin)
        if let rename = actions.rename {
            Button("Umbenennen …", action: rename)
        }
        if let reveal = actions.reveal {
            Button(revealedText == nil ? LocalizedStringKey("Anzeigen") : LocalizedStringKey("Verbergen"), action: reveal)
        }
        if let markNotSensitive = actions.markNotSensitive {
            Button("Nicht sensibel", action: markNotSensitive)
        }
        Divider()
        Button("Löschen", role: .destructive, action: actions.delete)
    }
}
