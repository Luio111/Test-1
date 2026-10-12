# Troubleshooting

## XcodeGen fehlt / Projekt fehlt

```sh
brew install xcodegen
cd CopyPal && ./scripts/bootstrap.sh
```

`CopyPal.xcodeproj` wird erzeugt und nie eingecheckt. Nach jedem Branch-Wechsel oder `git pull` erneut `./scripts/bootstrap.sh` ausführen.

## „xcodebuild requires Xcode, but active developer directory … is a command line tools instance“

Homebrew stellt das aktive Developer-Verzeichnis manchmal auf die Command Line Tools um:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

## Signierung: „Signing for "CopyPal" requires a development team“

`DEVELOPMENT_TEAM` in `Config/Signing.local.xcconfig` ist leer. Ein kostenloses „Personal Team“ reicht:

1. Xcode → Settings… → Accounts → „+“ → Apple ID (falls noch nicht angemeldet).
2. Team „… (Personal Team)“ auswählen → Manage Certificates… → „+“ → **Apple Development**.
   (Das Anmelden allein legt noch kein Zertifikat an.)
3. `./scripts/bootstrap.sh` erneut ausführen – es erkennt die Team-ID jetzt und trägt sie ein.

Von Hand: Team-ID anzeigen und in `Config/Signing.local.xcconfig` als `DEVELOPMENT_TEAM = …` eintragen:

```sh
security find-certificate -a -c "Apple Development" -p | openssl x509 -noout -subject
```

Die Team-ID ist der Wert hinter `OU=` (10 Zeichen) – nicht die ID in Klammern hinter deinem Namen.

Falls Xcode meldet, die Bundle-ID sei vergeben: in `Config/Signing.local.xcconfig` einen eigenen `BUNDLE_ID_PREFIX` setzen (z. B. `io.github.<dein-name>`).

## Bedienungshilfen-Freigabe geht nach jedem Build verloren

Ursache: Die App ist ad hoc signiert („Sign to Run Locally“). macOS bindet die Freigabe an die Signatur.

- Die Diagnose (Menüleiste → Diagnose …) muss bei **Signatur** „Stabil“ mit deiner Team-ID zeigen.
- Prüfen im Terminal:
  ```sh
  codesign -dv --verbose=4 ~/Library/Developer/Xcode/DerivedData/CopyPal-*/Build/Products/Debug/CopyPal.app 2>&1 | grep -E 'Authority|TeamIdentifier'
  ```
  Erwartet: `Authority=Apple Development: …` und deine `TeamIdentifier`.

## Freigabe hängt (Häkchen gesetzt, aber Diagnose zeigt „Nicht erteilt“)

1. CopyPal beenden.
2. `tccutil reset Accessibility <bundle-id>` (Debug: `<prefix>.CopyPal.dev`)
3. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen: alten CopyPal-Eintrag mit „–“ entfernen.
4. CopyPal starten → Diagnose → „Anfragen“.

Alles auf einmal zurücksetzen: `./scripts/reset-dev-state.sh`

## Kein Symbol in der Menüleiste

Auf MacBooks mit Notch blendet macOS Menüleisten-Symbole aus, wenn die Menüs der vorderen App (z. B. Xcode) viel Platz brauchen.

- Zum Finder wechseln – dann ist meist genug Platz.
- Andere Symbole mit gedrückter ⌘-Taste aus der Menüleiste ziehen.
- CopyPal erneut öffnen (Finder, Spotlight oder `open`): Das öffnet die Diagnose.

## Weitere Befehle

| Zweck | Befehl |
|---|---|
| Logs live ansehen | `log stream --predicate 'subsystem == "<bundle-id>"' --level debug` |
| Wer hat „Sichere Eingabe“ aktiv? | `ioreg -l -w 0 \| grep -i SecureInput` |
| Bundle-ID einer App | `osascript -e 'id of app "1Password"'` |
| Notarisierung prüfen (ab M9) | `spctl -a -vvv -t install CopyPal.dmg` |
