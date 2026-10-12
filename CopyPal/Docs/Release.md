# Release: Developer ID, Notarisierung, Sparkle (M9)

Alles läuft auf deinem Mac (`scripts/release.sh`), damit Zertifikate und Schlüssel nie in die CI müssen.

## Einmalig einrichten

### 1. Apple Developer Program (D10)

- Anmelden unter developer.apple.com/programs (99 $ pro Jahr). Als Einzelperson ist der Zugang sofort aktiv; als Organisation braucht es eine D-U-N-S-Nummer und mehrere Wochen Vorlauf.
- Endgültige Bundle-ID festlegen (D8), z. B. `de.<deinname>.CopyPal`, und in `Config/Signing.local.xcconfig` als `BUNDLE_ID_PREFIX` eintragen.
- Achtung: Mit dem neuen Team ändert sich die Signatur. Die Bedienungshilfen-Freigabe muss einmal neu erteilt werden. Den Entwicklungs-Verlauf legt CopyPal dann beiseite (neuer Schlüssel); das ist erwartet.

### 2. Zertifikat „Developer ID Application“

Xcode → Settings… → Accounts → dein Team → Manage Certificates… → „+“ → **Developer ID Application**.

Prüfen: `security find-identity -v -p codesigning` zeigt „Developer ID Application: … (TEAMID)“.

### 3. Zugang für die Notarisierung

App-spezifisches Passwort unter account.apple.com erstellen, dann:

```sh
xcrun notarytool store-credentials CopyPal --apple-id <deine-apple-id> --team-id <TEAMID>
```

### 4. Update-Schlüssel (Sparkle)

```sh
./scripts/release.sh --setup-sparkle
```

- Den angezeigten **öffentlichen** Schlüssel in `Config/Release.xcconfig` als `COPYPAL_SPARKLE_PUBLIC_KEY` eintragen und committen.
- Der **private** Schlüssel liegt im Schlüsselbund. Sichere ihn an **zwei** Orten (R19), z. B. Passwortmanager und verschlüsselter USB-Stick:

  ```sh
  build/sparkle-2.9.6/bin/generate_keys -x sparkle-private-key.txt
  ```

  Danach die Datei löschen. Ohne diesen Schlüssel kann CopyPal nie wieder Updates verteilen.
- **Wiederherstellung ausprobieren** (Fertig-wenn-Punkt in M9): in einem zweiten Benutzerkonto `generate_keys -f sparkle-private-key.txt` und prüfen, dass `generate_keys -p` denselben öffentlichen Schlüssel zeigt.

### 5. Feed-Adresse (Appcast)

- GitHub Pages für das Repository einschalten (Settings → Pages → Branch `gh-pages`).
- Die Adresse, z. B. `https://<name>.github.io/<repo>/appcast.xml`, in `Config/Release.xcconfig` als `COPYPAL_FEED_URL` eintragen.
- Vor der Beta das Repository umziehen (D1). Das öffentliche Website-Repository kann zugleich Appcast und Landingpage (`CopyPal/Website/`) hosten.

## Release bauen

```sh
./scripts/release.sh 0.9.0          # Beta-Kanal: ./scripts/release.sh 0.9.1 --beta
```

Das Skript:

1. prüft alle Voraussetzungen,
2. baut das Archiv,
3. exportiert mit Developer ID,
4. notarisiert und stapelt die App,
5. erstellt das DMG, signiert, notarisiert und stapelt es,
6. prüft das DMG mit `spctl`,
7. erzeugt den Appcast.

Danach:

1. GitHub-Release `v0.9.0` anlegen und das DMG anhängen.
2. `build/release/0.9.0/appcast.xml` nach `gh-pages` kopieren.
3. Prüfen:
   - `spctl -a -vvv -t install CopyPal-0.9.0.dmg` meldet „Notarized Developer ID“.
   - Das DMG öffnet sich auf einem anderen Mac oder Benutzerkonto ohne Gatekeeper-Blockade.
   - Ein Update von 0.9.0 auf 0.9.1 klappt über „Nach Updates suchen …“. Die Bedienungshilfen-Freigabe bleibt erhalten, weil Team und Bundle-ID gleich bleiben.

## Was Sparkle in CopyPal tut

- Ohne Feed-URL und öffentlichen Schlüssel startet der Updater gar nicht (Debug-Builds nie).
- Vor der ersten automatischen Prüfung fragt Sparkle um Erlaubnis. Es sendet kein Systemprofil (`SUEnableSystemProfiling = NO`).
- Beta-Versionen nur mit „Beta-Versionen erhalten“ (Einstellungen → Über), über den Appcast-Kanal `beta`.
