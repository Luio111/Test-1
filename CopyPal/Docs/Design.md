# CopyPal – Design

Leitbild: **clean, reduziert, Notion-artig.** Inhalt steht im Vordergrund, die Oberfläche tritt zurück.

## Prinzipien

1. **Ruhige Flächen.** Weiß bzw. sehr dunkles Grau, keine Verläufe, keine harten Schatten. Gliederung über Weißraum und feine Trennlinien statt Kästen.
2. **Hierarchie über Typografie.** Größe, Gewicht und Grauabstufung statt Farbe. Ein Titel pro Ansicht.
3. **Eine Akzentfarbe.** Blau nur für die eine Hauptaktion pro Ansicht. Status über dezente Tags (Notion-Stil: getönter Hintergrund, dunkle Schrift).
4. **Warme Grautöne.** Text nie reines Schwarz (`#37352F`), sekundärer Text `#787774`.
5. **Icons sparsam.** SF Symbols in normaler Strichstärke, in Sekundärgrau.
6. **Kurze Bewegung.** 150 ms ease-out für Hover/Zustände; Notch-Animation als Feder (M7).
7. **Hell und dunkel gleichwertig.** Jede Farbe ist als Paar definiert.

## Tokens

Quelle im Code: `App/DesignSystem/Theme.swift`.

| Token | Hell | Dunkel | Verwendung |
|---|---|---|---|
| `background` | `#FFFFFF` | `#191919` | Fensterfläche |
| `surface` | `#F7F7F5` | `#202020` | Callouts, Seitenleisten |
| `textPrimary` | `#37352F` | `#FFFFFF` · 81 % | Fließtext, Werte |
| `textSecondary` | `#787774` | `#9B9B9B` | Labels, Beschreibungen |
| `textTertiary` | `#A5A29C` | `#6F6F6F` | Fußnoten |
| `divider` | `#37352F` · 9 % | `#FFFFFF` · 9 % | Trennlinien, Rahmen |
| `hover` | `#37352F` · 6 % | `#FFFFFF` · 5,5 % | Hover-Hintergrund |
| `accent` | `#2383E2` | `#2383E2` | Hauptaktion |

**Tags** (Hintergrund / Schrift, hell): grau `#E3E2E0`/`#32302C` · grün `#DBEDDB`/`#1C3829` · orange `#FADEC9`/`#49290E` · rot `#FFE2DD`/`#5D1715` · blau `#D3E5EF`/`#183347`. Im Dunkelmodus kräftigere Hintergründe mit heller Schrift.

**Typografie** (SF Pro): Titel 24 bold · Text 14 · Text hervorgehoben 14 medium · Label 12 medium · Fußnote 12 · Code/IDs 12 SF Mono.

**Abstände:** 2 · 4 · 8 · 12 · 16 · 24 · 32. **Radien:** Tag 4 · Bedienelement 6 · Panel 12.

## Komponenten

Quelle: `App/DesignSystem/Components.swift`.

| Komponente | Zweck |
|---|---|
| `SectionBlock` | Abschnitt mit kleinem grauem Label |
| `PropertyRow` | Label/Wert-Zeile wie Notion-Eigenschaften, optional mit Icon |
| `StatusTag` | Zustand als getönter Tag |
| `Hairline` | 1-px-Trennlinie |
| `SubtleButtonStyle` | Sekundäraktion: Rahmen, Hover-Hintergrund |
| `PrimaryButtonStyle` | Hauptaktion: Akzentfarbe gefüllt |

## Offen

- **Pop-up aus der Notch (M4/M7):** Variante A „dunkel wie die Notch“ (nahtloser Übergang, immer dunkel) oder Variante B „folgt dem System“ (hell/dunkel, mit dunklem Übergang an der Notch). Entscheidung anhand eines klickbaren Entwurfs vor M4.
- App-Icon und Menüleisten-Icon (nach der Namensprüfung, D8). Bis dahin SF Symbol `doc.on.clipboard`.
