# CopyPal

Nativer Clipboard-Manager für den Mac: **⌘V tippen** fügt wie gewohnt ein, **⌘V halten** öffnet den Verlauf aus der Notch.

Plan und Stand: [Docs/ROADMAP.md](Docs/ROADMAP.md) · Design: [Docs/Design.md](Docs/Design.md) · Probleme: [Docs/Troubleshooting.md](Docs/Troubleshooting.md)

## Voraussetzungen

- macOS 14 oder neuer, Xcode 16 oder neuer
- [Homebrew](https://brew.sh) und XcodeGen: `brew install xcodegen`
- In Xcode mit deiner Apple-ID angemeldet (Xcode → Einstellungen → Accounts). Das kostenlose „Personal Team“ reicht.

## Loslegen

```sh
cd CopyPal
./scripts/bootstrap.sh --open
```

Das Skript legt `Config/Signing.local.xcconfig` an (bleibt lokal, wird nicht eingecheckt), trägt deine Team-ID ein, wenn es sie findet, und erzeugt `CopyPal.xcodeproj`. Danach in Xcode **⌘R**.

`CopyPal.xcodeproj` wird nie eingecheckt. Nach jedem `git pull` erneut `./scripts/bootstrap.sh` ausführen.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `App/` | App-Target: Menüleiste, Fenster, SwiftUI-Ansichten, Design-System |
| `Packages/CopyPalKit/` | Logik als Swift-Package: `CopyPalCore` (plattformneutral), `CopyPalStorage`, `CopyPalSystem` (macOS-Adapter), `CopyPalServices` |
| `Config/` | Build-Einstellungen (`.xcconfig`) |
| `scripts/` | `bootstrap.sh`, `reset-dev-state.sh` |
| `Docs/` | Roadmap, Design, Entscheidungen (ADR), Testpläne, Troubleshooting |

## Tests

```sh
swift test --package-path Packages/CopyPalKit
```

Die CI (`.github/workflows/copypal-ci.yml`) führt die Package-Tests unter Linux und macOS aus und baut die App bei jedem Pull Request.
