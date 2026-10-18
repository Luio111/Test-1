# CopyPal – Design

Leitbild: **clean, reduziert, Notion-artig.** Inhalt steht im Vordergrund, die Oberfläche tritt zurück.

## Prinzipien

1. **Ruhige Flächen.** Weiß bzw. sehr dunkles Grau, keine Verläufe, keine harten Schatten. Gliederung über Weißraum und feine Trennlinien statt Kästen.
2. **Hierarchie über Typografie.** Größe, Gewicht und Grauabstufung statt Farbe. Ein Titel pro Ansicht.
3. **Eine Akzentfarbe.** Blau nur für die eine Hauptaktion pro Ansicht. Status über dezente Tags (Notion-Stil: getönter Hintergrund, dunkle Schrift).
4. **Warme Grautöne.** Text nie reines Schwarz (`#37352F`), sekundärer Text `#73726E`.
5. **Icons sparsam.** SF Symbols in normaler Strichstärke, in Sekundärgrau.
6. **Kurze Bewegung.** 150 ms ease-out für Hover/Zustände; Notch-Animation als Feder (M7).
7. **Hell und dunkel gleichwertig.** Jede Farbe ist als Paar definiert.
8. **Lesbar für alle.** Text mit Information erreicht WCAG AA (≥ 4,5:1); dekorative Icons sind für VoiceOver ausgeblendet.

## Tokens

Quelle im Code: `App/DesignSystem/Theme.swift`.

| Token | Hell | Dunkel | Verwendung |
|---|---|---|---|
| `background` | `#FFFFFF` | `#191919` | Fensterfläche |
| `surface` | `#F7F7F5` | `#202020` | Callouts, Seitenleisten |
| `textPrimary` | `#37352F` | `#FFFFFF` · 81 % | Fließtext, Werte |
| `textSecondary` | `#73726E` | `#9B9B9B` | Labels, Beschreibungen, Fußnoten (4,8:1 bzw. 6,3:1) |
| `textTertiary` | `#A5A29C` | `#6F6F6F` | nur dekorativ (Platzhalter, deaktiviert) – zu wenig Kontrast für Information |
| `divider` | `#37352F` · 9 % | `#FFFFFF` · 9 % | Trennlinien, Rahmen |
| `hover` | `#37352F` · 6 % | `#FFFFFF` · 5,5 % | Hover-Hintergrund |
| `pressed` | `#37352F` · 12 % | `#FFFFFF` · 10 % | gedrückter Zustand |
| `accent` | `#2383E2` | `#2383E2` | Akzent (Fokus, Links) |
| `accentFill` · Hover · Gedrückt | `#1C6FC2` · `#1A6AB8` · `#165FA6` | gleich | Fläche der Hauptaktion (weiße Schrift ≥ 5,1:1) |

**Tags** (Hintergrund / Schrift, hell): grau `#E3E2E0`/`#32302C` · grün `#DBEDDB`/`#1C3829` · orange `#FADEC9`/`#49290E` · rot `#FFE2DD`/`#5D1715` · blau `#D3E5EF`/`#183347`. Im Dunkelmodus kräftigere Hintergründe mit heller Schrift.

**Typografie** (SF Pro): Titel 24 bold · Text 14 · Text hervorgehoben 14 medium · Label 12 medium · Fußnote 12 · Code/IDs 12 SF Mono.

**Abstände:** 2 · 4 · 8 · 12 · 16 · 24 · 32. **Radien:** Tag 4 · Bedienelement 6 · Panel 12.

**Layout** (`Theme.Layout`): Seitenrand 40 · oberer Rand 44 (transparente Titelleiste) · Zeilenabstand vertikal 6 · Label-Spalte 168 · Diagnose-Fenster 620 × 680.

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

## Pop-up an der Notch

Entschieden (12.10.2026): **Variante A „dunkel wie die Notch“.** Das Pop-up ist die Notch selbst, die nach unten wächst – immer schwarz, ohne Rand, nahtlos an der Kamera.

- **Form** (`App/Notch/NotchShape.swift`): bündig an der Oberkante, oben konkave Ausläufer (8 pt) wie bei der Notch, unten Radius 20. Ohne Notch dieselbe Form oben mittig, so hoch wie die Menüleiste.
- **Aufbau, flach:** In der Höhe der Notch links die Suche, rechts „Verlauf | Favoriten“, die Mitte bleibt frei für die Kamera. Darunter bis zu 8 Zeilen à 28 pt, unten eine Hinweiszeile (26 pt). Breite 520 pt (breiter, wenn die Notch es verlangt).
- **Farben** (`Theme.Notch`): Weiß 92 % Text, 60 % sekundär (6,3:1), 40 % nur dekorativ, Auswahl 14 %, Flächen 10 %.
- **Bewegung** (`PopupMotion`): Öffnen als Feder 0,42 s mit leichtem Nachfedern („fällt“ aus der Notch), die Form deckt den Inhalt dabei auf, Zeilen folgen mit 18 ms Versatz. Schließen: Inhalt sofort weg, die schwarze Form zieht sich in 0,26 s zurück (eigenes, passives Fenster, damit Fokus und Einfügen sofort bei der App sind). „Bewegung reduzieren“ oder die Einstellung schaltet alles ab.
- **Maus:** Darüberfahren wählt eine Zeile aus (erst nach einer echten Mausbewegung), Klick fügt ein. „Verlauf“ und „Favoriten“ neben der Notch sind anklickbar (wie ⇥).
- **Hinweiszeile:** ⌘P heißt „Favorit hinzufügen“ bzw. „Favorit entfernen“, je nach ausgewähltem Eintrag.

## Bildschirmfoto-Overlay (M11)

Das Overlay gehört zur Notch-Welt: immer dunkel, eine Akzentfarbe, Werte in SF Mono.

- **Abdunkeln:** Schwarz 45 % über dem eingefrorenen Bild – heller als übliche Screenshot-Tools, damit der Inhalt zum Einrasten lesbar bleibt. Markierter Kandidat und Auswahl bleiben ungedunkelt.
- **Kandidat:** 1,5 pt `accent` (#2383E2) plus 8 % Füllung, Radius 4; die einzige Akzentfarbe im Overlay. 150 ms ease-out beim Wechsel, nichts bei „Bewegung reduzieren“ oder ausgeschalteter Animation.
- **Auswahl:** 1 px Weiß 92 %; vier runde Ecken-Griffe 6 pt Weiß 92 % mit 0,5 pt schwarzem Ring, erst nach dem Loslassen.
- **Kapseln:** Schwarz, Höhe 26, ganz gerundet. Größe „1.280 × 720“ in SF Mono 12 Weiß 92 % unter der Auswahl (darüber, wenn unten kein Platz ist). Status und Hinweiszeile unten mittig auf dem Bildschirm, an dem gearbeitet wird; Status Weiß 92 %, Hinweis Weiß 60 %. Keine farbigen Punkte, keine Symbole.
- **Erweitern:** Das aktuelle Bild erscheint direkt in der Auswahl; keine zweite Vorschau.
- **Zeiger:** Fadenkreuz, nie versteckt. Koordinaten „412, 318“ neben dem Zeiger, solange nichts markiert ist.
- **Ergebnis:** die bekannte Kapsel an der Notch, „Bildschirmfoto kopiert“ mit `camera.viewfinder`.
- **Berechtigungsfenster:** Aufbau wie das Onboarding (`PageHeader`, `StatusTag`, eine Hauptaktion), damit es als Teil von CopyPal erkennbar ist.

## Kürzel-Karte unter dem Menüleisten-Symbol

Ruht der Zeiger 0,35 s auf dem Symbol, erscheint darunter eine kleine Karte – wie die Kapseln an der Notch schwarz, Radius 12, 1-px-Rand Weiß 8 %. Sie ersetzt den Tooltip.

- **Zeilen:** links der Name in Weiß 60 % („Verlauf-Pop-up“, „Bildschirmfoto“), rechts die Kürzel als Tasten-Kappen (Weiß 10 %, Radius 4, Schrift 12 medium Weiß 92 %), dahinter „halten“, „oder“, „belegt“ bzw. „aus“ in Weiß 60 %.
- **Status:** Fehlt eine Berechtigung oder ist die Aufzeichnung pausiert, steht das oben, durch eine Linie getrennt.
- **Verhalten:** ignoriert die Maus, verschwindet beim Verlassen und sobald das Menü aufgeht; 120 ms Ein- und Ausblenden (aus bei „Bewegung reduzieren“). VoiceOver liest denselben Inhalt als Hilfe des Symbols.

## Offen

- App-Icon und Menüleisten-Icon (nach der Namensprüfung, D8). Bis dahin SF Symbol `doc.on.clipboard`.
