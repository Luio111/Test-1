# Troubleshooting

## XcodeGen fehlt / Projekt fehlt

```sh
brew install xcodegen
cd CopyPal && ./scripts/bootstrap.sh
```

`CopyPal.xcodeproj` wird erzeugt und nie eingecheckt. Nach jedem `git pull` erneut `./scripts/bootstrap.sh` ausführen.

## Signierung: „Signing for "CopyPal" requires a development team“

1. Xcode → Einstellungen → Accounts → mit deiner Apple-ID anmelden (kostenloses „Personal Team“ reicht).
2. Team-ID herausfinden:
   ```sh
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```
   Die Team-ID steht hinter `OU=` (10 Zeichen).
3. In `Config/Signing.local.xcconfig` eintragen: `DEVELOPMENT_TEAM = ABCDE12345`
4. `./scripts/bootstrap.sh` erneut ausführen.

Falls Xcode meldet, die Bundle-ID sei vergeben: in `Config/Signing.local.xcconfig` einen eigenen `BUNDLE_ID_PREFIX` setzen (z. B. `io.github.<dein-name>`).

## Bedienungshilfen-Freigabe geht nach jedem Build verloren

Ursache: Die App ist ad hoc signiert („Sign to Run Locally“). macOS bindet die Freigabe an die Signatur.

- Die Diagnose (Menüleiste → Diagnose …) muss bei **Signatur** „Stabil“ mit deiner Team-ID zeigen.
- Prüfen im Terminal:
  ```sh
  codesign -dv --verbose=4 <Pfad>/CopyPal.app 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier'
  ```
  Erwartet: `Authority=Apple Development: …` und deine `TeamIdentifier`. Den Pfad zeigt Xcode unter Product → Show Build Folder in Finder.

## Freigabe hängt (Häkchen gesetzt, aber Diagnose zeigt „Nicht erteilt“)

1. CopyPal beenden.
2. `tccutil reset Accessibility <bundle-id>` (Debug: `<prefix>.CopyPal.dev`)
3. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen: alten CopyPal-Eintrag mit „–“ entfernen.
4. CopyPal starten → Diagnose → „Anfragen“.

Alles auf einmal zurücksetzen: `./scripts/reset-dev-state.sh`

## Weitere Befehle

| Zweck | Befehl |
|---|---|
| Logs live ansehen | `log stream --predicate 'subsystem == "<bundle-id>"' --level debug` |
| Wer hat „Sichere Eingabe“ aktiv? | `ioreg -l -w 0 \| grep -i SecureInput` |
| Bundle-ID einer App | `osascript -e 'id of app "1Password"'` |
| Notarisierung prüfen (ab M9) | `spctl -a -vvv -t install CopyPal.dmg` |
