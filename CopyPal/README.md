# CopyPal

Nativer Clipboard-Manager für den Mac: **⌘V tippen** fügt wie gewohnt ein, **⌘V halten** öffnet den Verlauf aus der Notch.

- **1–8** fügt den Eintrag ein, **⇧** ohne Formatierung, Tippen sucht, **⇥** zeigt die Favoriten, **⌘P** macht ihn zum Favoriten.
- Alles bleibt **verschlüsselt auf diesem Mac**: AES-GCM, der Schlüssel liegt im Schlüsselbund. Kein Netz, keine Statistik.
- Passwortmanager werden nie gespeichert. IBAN, Kartennummern, API-Schlüssel und Einmalcodes werden verdeckt und nach einer Minute gelöscht.
- **⌃⌥V** öffnet den Verlauf auch ohne Bedienungshilfen-Freigabe.
- **⌘⇧A** macht ein Bildschirmfoto: Klick nimmt Fenster oder Bereich auf, Ziehen wählt frei, **↓** nimmt auch auf, was unterhalb noch nicht sichtbar ist.

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

## Neuesten Stand holen

Ein Befehl, egal in welchem Ordner du gerade bist:

```sh
copypal-update
```

Er holt den CopyPal-Branch von GitHub (sobald der in `main` gemergt ist: `main`) und legt lokale Änderungen, meist von Xcode, beiseite (`git stash`). Dann erzeugt er `CopyPal.xcodeproj` neu und öffnet Xcode. Dort **⌘R** drücken. Eigene Commits sichert er vorher im Branch `copypal-sicherung-…`.

Einmalig einrichten: Diese Zeile ins Terminal kopieren. Sie sucht das Repository in `~/Developer/Test-1`, `~/Test-1`, `~/Documents/Test-1` und `~/Desktop/Test-1`, sonst im Ordner, in dem du gerade stehst:

```sh
d=; for c in ~/Developer/Test-1 ~/Test-1 ~/Documents/Test-1 ~/Desktop/Test-1; do [ -d "$c/.git" ] && d=$c && break; done; [ -n "$d" ] || d="$(git rev-parse --show-toplevel 2>/dev/null)"; s=; if [ -n "$d" ]; then for b in claude/amazing-volta-1uce5i main; do GIT_TERMINAL_PROMPT=0 git -C "$d" fetch -q origin "+refs/heads/${b}:refs/copypal/${b}" 2>/dev/null && s="$(git -C "$d" show "refs/copypal/${b}:CopyPal/scripts/update.sh" 2>/dev/null)" && break; done; fi; if [ -n "$s" ]; then COPYPAL_REPO="$d" bash -c "$s" update.sh --install; elif [ -z "$d" ]; then echo "Ordner Test-1 nicht gefunden (gesucht: ~/Developer, ~, ~/Documents, ~/Desktop und der aktuelle Ordner)"; else echo "GitHub nicht erreichbar, nicht angemeldet (gh auth login) oder der Branch wurde umbenannt"; fi
```

Danach ein neues Terminal-Fenster öffnen. Fehlt der Befehl später einmal (neuer Mac, verschobener Ordner), einfach die Zeile erneut einfügen – sie aktualisiert ebenfalls.

- **Anderen Branch testen:** `COPYPAL_BRANCH=<branch> copypal-update` (gibt es den Branch nicht, bricht der Befehl ab)
- **Xcode nicht öffnen:** `copypal-update --no-open`

`CopyPal.xcodeproj` wird erzeugt und nie eingecheckt. Wer von Hand pullt oder den Branch wechselt, muss danach `./scripts/bootstrap.sh` ausführen. Die Checkliste steht im PR bzw. in `Docs/Testplaene/`.

## Aufbau

| Ordner | Inhalt |
|---|---|
| `App/` | App-Target: Menüleiste, Fenster, SwiftUI-Ansichten, Design-System |
| `Packages/CopyPalKit/` | Logik als Swift-Package: `CopyPalCore` (plattformneutral), `CopyPalStorage`, `CopyPalSystem` (macOS-Adapter), `CopyPalServices` |
| `Config/` | Build-Einstellungen (`.xcconfig`) |
| `scripts/` | `update.sh` (`copypal-update`), `bootstrap.sh`, `reset-dev-state.sh`, `ci-check-warnings.sh` |
| `Docs/` | Roadmap, Design, Entscheidungen (ADR), Testpläne, Troubleshooting |

## Tests

```sh
swift test --package-path Packages/CopyPalKit
```

Unter Linux zusätzlich `-Xswiftc -DSQLITE_DISABLE_SNAPSHOT` und das Paket `libsqlite3-dev` (siehe [ADR 0004](Docs/ADR/0004-grdb-linux-und-einstellungen.md)).

Die CI (`.github/workflows/copypal-ci.yml`) läuft bei jedem Pull Request:

1. testet das Package unter Linux und macOS,
2. baut die App,
3. führt den **Selbsttest** auf einem echten Mac aus: Erfassen, Datenschutz, Verlauf, ⌘V tippen und halten, Pop-up, Suche, Favoriten, Verschlüsselung auf der Platte, 100 schnelle Kopien, großes Bild.

Compiler-Warnungen im eigenen Code lassen die CI scheitern.

Übersetzungen (`App/Resources/Localizable.xcstrings`, Deutsch → Englisch) pflegt `scripts/check-localization.py`: Die CI scheitert, wenn ein Text keine englische Übersetzung hat oder die Datei nicht sortiert ist (`--fix` sortiert). Xcode schreibt die Datei beim Bauen nicht um (`SWIFT_EMIT_LOC_STRINGS = NO`), damit `git pull` nie an ihr hängen bleibt.

Den Selbsttest auf macOS 14 (älteste unterstützte Version) startest du von Hand: Actions → „CopyPal CI“ → Run workflow → „Zusätzlich Selbsttest auf macOS 14“ anhaken.

Den Selbsttest kannst du auch selbst starten (Debug-Build, braucht die Bedienungshilfen-Freigabe für das Terminal). Er nutzt einen eigenen, temporären Verlauf und eigene Einstellungen, schreibt aber in die echte Zwischenablage:

```sh
~/Library/Developer/Xcode/DerivedData/CopyPal-*/Build/Products/Debug/CopyPal.app/Contents/MacOS/CopyPal --self-test
```
