import AppKit
import SwiftUI
import CopyPalCore
import CopyPalSystem

/// The markup window's content (ROADMAP R33, Docs/Design.md "Markieren"): the tools
/// on top, colour and size of what is drawn below them, the picture, and the way out
/// at the bottom. Every tool and button names its key in its tooltip.
struct AnnotationEditorView: View {
    let model: AnnotationEditorModel
    let canvas: AnnotationCanvasView

    var body: some View {
        VStack(spacing: 0) {
            toolRow
            Hairline()
            styleRow
            Hairline()
            AnnotationCanvasHost(canvas: canvas)
            Hairline()
            bottomRow
        }
        .background(Color(nsColor: Theme.Colors.windowBackground))
    }

    // MARK: Tools

    private static let toolGroups: [[AnnotationTool]] = [
        [.select],
        [.pen, .highlighter],
        [.arrow, .line, .rectangle, .ellipse],
        [.text],
    ]

    private var toolRow: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(Self.toolGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    groupDivider
                }
                ForEach(group, id: \.self) { tool in
                    EditorIconButton(
                        symbol: tool.symbol,
                        label: tool.title,
                        keys: String(tool.key).uppercased(),
                        selected: model.tool == tool
                    ) {
                        model.selectTool(tool)
                    }
                }
            }
            Spacer(minLength: Theme.Spacing.m)
            EditorIconButton(symbol: "arrow.uturn.backward", label: String(localized: "Rückgängig"), keys: "⌘Z", enabled: model.canUndo) {
                model.undo()
            }
            EditorIconButton(symbol: "arrow.uturn.forward", label: String(localized: "Wiederholen"), keys: "⇧⌘Z", enabled: model.canRedo) {
                model.redo()
            }
            groupDivider
            EditorIconButton(symbol: "trash", label: String(localized: "Markierung löschen"), keys: "⌫", enabled: model.selection != nil) {
                model.deleteSelection()
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var groupDivider: some View {
        Rectangle()
            .fill(Theme.Colors.divider)
            .frame(width: 1, height: 18)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    // MARK: Style

    private var styleRow: some View {
        HStack(spacing: Theme.Spacing.l) {
            if model.styleTool == .select {
                Text("Eine Markierung anklicken, um sie zu ändern – oder ein Werkzeug wählen.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                colorControls
                sizeControl
                if model.styleTool.canFill {
                    Toggle(isOn: Binding(get: { model.style.filled }, set: { value in model.changeStyle { $0.filled = value } })) {
                        Text("Füllen")
                    }
                    .toggleStyle(.checkbox)
                }
                if model.styleTool == .text {
                    Toggle(isOn: Binding(get: { model.style.textBackground }, set: { value in model.changeStyle { $0.textBackground = value } })) {
                        Text("Sprechblase")
                    }
                    .toggleStyle(.checkbox)
                    .help(Text("Text auf einer Fläche in der gewählten Farbe"))
                }
            }
            Spacer(minLength: 0)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(height: 28)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.xs + 2)
    }

    private var colorControls: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            ForEach(AnnotationColor.palette, id: \.self) { color in
                ColorSwatch(color: color, selected: model.style.color == color) {
                    model.changeStyle { $0.color = color }
                }
            }
            ColorPicker(selection: colorBinding, supportsOpacity: false) {
                Text("Eigene Farbe")
            }
            .labelsHidden()
            .help(Text("Eigene Farbe"))
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(cgColor: AnnotationRenderer.cgColor(model.style.color)) },
            set: { newValue in
                guard let srgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                let color = AnnotationColor(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
                model.changeStyle(coalescing: true) { $0.color = color }
            }
        )
    }

    private var sizeControl: some View {
        let tool = model.styleTool
        let range = tool.usesFontSize ? AnnotationStyle.fontSizeRange : AnnotationStyle.widthRange(for: tool)
        let step = AnnotationStyle.sizeStep(for: tool)
        let size = Binding<Double>(
            get: { tool.usesFontSize ? model.style.fontSize : model.style.lineWidth },
            set: { value in
                model.changeStyle { style in
                    if tool.usesFontSize {
                        style.fontSize = value
                    } else {
                        style.lineWidth = value
                    }
                }
            }
        )
        let title = tool.usesFontSize ? String(localized: "Schriftgröße") : String(localized: "Strichstärke")
        return HStack(spacing: Theme.Spacing.s) {
            Text(verbatim: title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Slider(value: size, in: range, step: step, onEditingChanged: { editing in
                model.adjustingStyle(editing)
            })
            .controlSize(.small)
            .frame(width: 130)
            .accessibilityLabel(Text(verbatim: title))
            Stepper(value: size, in: range, step: step) {
                Text(verbatim: title)
            }
            .labelsHidden()
            .controlSize(.small)
            Text(verbatim: "\(Int(size.wrappedValue)) pt")
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
        }
        .help(Text("[ und ] ändern die Größe"))
    }

    // MARK: Bottom

    private var bottomRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            hint
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.m)
            Button {
                model.finish(.cancel)
            } label: {
                Text("Abbrechen")
            }
            .buttonStyle(SubtleButtonStyle())
            Button {
                model.finish(.save)
            } label: {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    Text("Sichern")
                    Text(verbatim: "⌘S")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .buttonStyle(SubtleButtonStyle())
            .help(Text("Kopieren und als Datei sichern"))
            Button {
                model.finish(.copy)
            } label: {
                HStack(spacing: Theme.Spacing.xs + 2) {
                    Text("Kopieren")
                    Text(verbatim: "⏎")
                        .opacity(0.8)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .help(Text("Bild mit Markierungen kopieren"))
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s + 2)
    }

    @ViewBuilder
    private var hint: some View {
        if model.editingText != nil {
            Text("Esc oder ⌘⏎: Text fertig · ⏎: neue Zeile")
        } else {
            switch model.tool {
            case .select:
                Text("Ziehen: verschieben · Doppelklick: Text ändern · Pfeiltasten: genau setzen")
            case .pen, .highlighter:
                Text("⇧: gerade Linie · [ ]: dünner, dicker")
            case .arrow, .line:
                Text("⇧: in 45°-Schritten · [ ]: dünner, dicker")
            case .rectangle, .ellipse:
                Text("⇧: Quadrat, Kreis · ⌥: von der Mitte · [ ]: dünner, dicker")
            case .text:
                Text("Klicken und tippen · [ ]: Schrift kleiner, größer")
            }
        }
    }
}

/// A square symbol button of the tool row; the selected tool is filled with the accent.
private struct EditorIconButton: View {
    let symbol: String
    let label: String
    let keys: String
    var selected = false
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 28)
                .foregroundStyle(selected ? Color.white : Theme.Colors.textPrimary)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(Text(verbatim: "\(label) (\(keys))"))
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var background: Color {
        if selected {
            return Theme.Colors.accentFill
        }
        return hovering && enabled ? Theme.Colors.hover : .clear
    }
}

/// One colour of the palette; the chosen one gets a ring.
private struct ColorSwatch: View {
    let color: AnnotationColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(cgColor: AnnotationRenderer.cgColor(color)))
                .overlay(Circle().strokeBorder(Theme.Colors.divider))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(
                    Circle()
                        .strokeBorder(selected ? Theme.Colors.accent : .clear, lineWidth: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: color.name ?? ""))
        .accessibilityLabel(Text(verbatim: color.name ?? String(localized: "Eigene Farbe")))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The canvas in a scroll view that fits it on every resize.
private struct AnnotationCanvasHost: NSViewRepresentable {
    let canvas: AnnotationCanvasView

    func makeNSView(context: Context) -> AnnotationScrollView {
        AnnotationScrollView(canvas: canvas)
    }

    func updateNSView(_ nsView: AnnotationScrollView, context: Context) {}
}

final class AnnotationScrollView: NSScrollView {
    private let canvas: AnnotationCanvasView

    init(canvas: AnnotationCanvasView) {
        self.canvas = canvas
        super.init(frame: .zero)
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = Theme.Colors.canvasBackground
        documentView = canvas
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func layout() {
        super.layout()
        canvas.fit(in: contentSize)
    }
}

extension AnnotationTool {
    var title: String {
        switch self {
        case .select: String(localized: "Auswählen")
        case .pen: String(localized: "Stift")
        case .highlighter: String(localized: "Textmarker")
        case .arrow: String(localized: "Pfeil")
        case .line: String(localized: "Linie")
        case .rectangle: String(localized: "Rechteck")
        case .ellipse: String(localized: "Ellipse")
        case .text: String(localized: "Text")
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        }
    }
}

extension AnnotationColor {
    /// The palette's colours by name (VoiceOver, tooltips); nil for a custom colour.
    var name: String? {
        switch self {
        case .red: String(localized: "Rot")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Gelb")
        case .green: String(localized: "Grün")
        case .blue: String(localized: "Blau")
        case .purple: String(localized: "Lila")
        case .black: String(localized: "Schwarz")
        case .white: String(localized: "Weiß")
        default: nil
        }
    }
}
