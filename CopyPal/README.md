# CopyPal

Nativer Clipboard-Manager für den Mac: **⌘V tippen** fügt wie gewohnt ein, **⌘V halten** öffnet den Verlauf aus der Notch.

Plan und Stand: [Docs/ROADMAP.md](Docs/ROADMAP.md) · Design: [Docs/Design.md](Docs/Design.md) · Probleme: [Docs/Troubleshooting.md](Docs/Troubleshooting.md)

## Voraussetzungen

- Xcode **16.3 oder neuer** (die App selbst läuft ab macOS 14)
- [Homebrew](https://brew.sh) und XcodeGen: `brew install xcodegen`
- Aktives Developer-Verzeichnis ist Xcode: `xcode-select -p` zeigt `/Applications/Xcode.app/…`, sonst `sudo xcode-select -s /Applications/Xcode.app`
- Apple ID in Xcode, kostenloses „Personal Team“ reicht:
  1. Xcode → Settings… → Accounts → „+“ → Apple ID
  2. Team „… (Personal Team)“ auswählen → Manage Certificates… → „+“ → **Apple Development**

## Loslegen

Repository einmalig auf den Mac holen (privat, daher mit GitHub-Anmeldung):

```sh
brew install gh
gh auth login                  # GitHub.com → HTTPS → Login with a web browser
mkdir -p ~/Developer && cd ~/Developer
gh repo clone Luio111/Test-1
cd Test-1
```

Dann im Ordner `Test-1`:

```sh
cd CopyPal
./scripts/bootstrap.sh --open
```

Das Skript legt `Config/Signing.local.xcconfig` an (bleibt lokal, wird nie eingecheckt), trägt deine Team-ID ein, wenn sie eindeutig ist, und erzeugt `CopyPal.xcodeproj`. Danach in Xcode **⌘R**.

## Einen Pull Request testen

Im Ordner `Test-1` (z. B. `cd ~/Developer/Test-1`):

```sh
git fetch origin
git switch <branch-aus-dem-PR>
cd CopyPal && ./scripts/bootstrap.sh
```

`CopyPal.xcodeproj` wird erzeugt und nie eingecheckt – nach jedem Branch-Wechsel oder `git pull` erneut `./scripts/bootstrap.sh` ausführen. Die Checkliste steht im PR bzw. in `Docs/Testplaene/`.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `App/` | App-Target: Menüleiste, Fenster, SwiftUI-Ansichten, Design-System |
| `Packages/CopyPalKit/` | Logik als Swift-Package: `CopyPalCore` (plattformneutral), `CopyPalStorage`, `CopyPalSystem` (macOS-Adapter), `CopyPalServices` |
| `Config/` | Build-Einstellungen (`.xcconfig`) |
| `scripts/` | `bootstrap.sh`, `reset-dev-state.sh`, `ci-check-warnings.sh` |
| `Docs/` | Roadmap, Design, Entscheidungen (ADR), Testpläne, Troubleshooting |

## Tests

```sh
swift test --package-path Packages/CopyPalKit
```

Die CI (`.github/workflows/copypal-ci.yml`) testet das Package unter Linux und macOS und baut die App bei jedem Pull Request. Compiler-Warnungen im eigenen Code lassen sie scheitern.
