# Ideen und Design-Review (CopyPal)

Stand 13.10.2026. Grundlage: 34 Ideen aus vier Blickwinkeln und 46 geprüfte Design-Befunde. Pfade unter `Packages/CopyPalKit/Sources/` sind gekürzt (zum Beispiel `CopyPalCore/…`).

## Kurzfassung

- **Texterkennung (Vision) als eine gemeinsame Schicht.** ⇧⏎ kopiert den Text einer Auswahl im Overlay. Bilder werden durchsuchbar und auf IBAN, Karten und Schlüssel geprüft. Damit schließt sich die Lücke aus D15. Nutzen 5, Aufwand M–L.
- **Pop-up aus Bildschirmfreigaben heraushalten, dazu ein Präsentationsmodus.** Wer im Meeting ⌘V hält, zeigt heute allen die letzten 8 Kopien. Das ist das wahrscheinlichste Datenleck im Alltag. Nutzen 4, Aufwand S–M.
- **Bildschirmfotos wiederfinden.** Statt „Bild 2880 × 1800“ mit CopyPal-Symbol zeigt die Zeile die Quell-App und den Fenstertitel. Die Suche findet dann auch App und Typ. Nutzen 4, Aufwand S.
- **Design-Fix 1: Ein Versprechen ist falsch.** Das Berechtigungsfenster sagt „Jedes Bildschirmfoto bleibt verschlüsselt auf diesem Mac“. Tatsächlich landen Bildschirmfotos unverschlüsselt in der Zwischenablage und gehen per Universal Clipboard ans iPhone. Der Text muss sich ändern.
- **Design-Fix 2: Der Kürzel-Rekorder löst das jeweils andere CopyPal-Kürzel aus, statt es abzulehnen.** Testplan M11, Schritt 23 schlägt deshalb fehl. Lösung: Beide Kürzel abmelden, solange der Rekorder aufnimmt.

## Empfohlene Erweiterungen

Sortiert nach Nutzen, bei gleichem Nutzen nach Aufwand. Doppelte Ideen sind zusammengeführt. **B** steht schon im Backlog (`Docs/ROADMAP.md:745-751`), **B\*** nur teilweise.

| # | Idee | Nutzen | Aufwand | Warum |
|---|---|---|---|---|
| 1 | Texterkennung: Text kopieren, Bilder durchsuchen, Sensibles in Bildern erkennen **B\*** | 5 | M–L | Schließt die Lücke aus D15. Meistgewünschte Bildschirmfoto-Funktion |
| 2 | Favoritennamen im Pop-up | 4 | S | Gleich beginnende Favoriten sehen identisch aus. Testplan M6 erwartet die Namen schon |
| 3 | Bildschirmfotos wiederfinden: Quell-App, Fenstertitel, Typ in der Suche | 4 | S | Die Suche findet heute kein einziges Bild |
| 4 | Pop-up in Bildschirmfreigaben verbergen + Präsentationsmodus | 4 | S–M | Sichtbarstes Leck im Alltag |
| 5 | Bildschirmfotos mit ignorierten Apps nur lokal speichern, später schwärzen | 4 | S–M | Ein 1Password-Fenster geht heute ans iPhone |
| 6 | Vorschau mit → im Pop-up | 4 | M | Bei ähnlichen Einträgen heißt es heute: raten, einfügen, rückgängig machen |
| 7 | Schwärzen im Overlay | 4 | M (L mit Vorschlägen) | Das ungeschwärzte Original landet heute im Verlauf |
| 8 | App-Regeln: „Kurzlebig“ und „Immer ohne Formatierung“ | 4 | M | Datenschutz pro App kennt heute nur an oder aus |
| 9 | Automation: Kurzbefehle, Fokus-Filter, `copypal://` nur für Aktionen | 4 | M | Raycast-, KM- und BTT-Nutzer haben keine Schnittstelle |
| 10 | Umwandeln im Pop-up (trimmen, eine Zeile, JSON, Markdown) | 4 | M | Will ebenfalls die Taste → (Konflikt mit #6) |
| 11 | Sensible Kopien: Hinweis, Restzeit, „⌘P behalten“ | 3 | S | Einträge verschwinden nach 60 s ohne Erklärung |
| 12 | ⇧ = reine Form (Pfad, sauberer Link, Hex), Tracking-Parameter entfernen **B** | 3 | S | Parameter wie utm_* und fbclid verraten, woher ein Link kommt |
| 13 | Tastatur-Notausgänge: „Letzte Kopie vergessen“, „Nächste Kopie nicht merken“, ⌥↩ | 3 | S | Löschen braucht heute Maus und Verlaufsfenster |
| 14 | Saubere Fensteraufnahme (ganzes Fenster, Schatten, transparente Ecken) | 3 | S | Heute sind überlappende Fenster und Desktop-Pixel mit im Bild |
| 15 | Selbstauslöser 3/5/10 s | 3 | S | Menüs und Tooltips fehlen in der frischen Aufnahme |
| 16 | Abschnitt „Bewusst nicht“ + geprüfte Spotlight-Abgrenzung (R22) | 3 | S | Beendet wiederkehrende Feature-Wünsche |
| 17 | Verlaufsfenster: Tastatur, ↩ fügt in die vorherige App ein, ⌘F aus dem Pop-up | 3 | M | Treffer 9–20 einer Pop-up-Suche sind heute unerreichbar |
| 18 | Favoriten neu anlegen und bearbeiten | 3 | M | Ein Tippfehler in einer Vorlage kostet heute fünf Schritte |
| 19 | Sammeln: markieren, verbunden einfügen oder als Warteschlange **B** | 3 | M | Ein Formular braucht heute N Pop-up-Runden |
| 20 | Ergebnis-Kapsel mit Vorschaubild zum Ziehen, „Sichern“, „Teilen“ **B\*** | 3 | M | Ein Bildschirmfoto kann heute keine Datei werden |
| 21 | Schweben lassen (Bild bleibt im Vordergrund) | 2 | S | Nützlich, aber eine Nische |
| 22 | Nach links/rechts erweitern **B** | 2 | M | Seltener als vertikal. Risiko: Browser deuten es als Zurück-Wischen |

**1 · Texterkennung.** Ein `TextRecognizer` in CopyPalSystem nutzt Vision (accurate, de+en, Sprachkorrektur aus, ohne Netzwerk).
- Stufe 1: ⇧⏎ oder ⇧-Klick im Overlay kopiert den Text, auch aus einer zusammengesetzten Scroll-Aufnahme. Toast: „Text kopiert · 6 Zeilen“. Der Text läuft durch die normale Erfassung, also greifen Maskierung, die 60-s-Löschung und „nur lokal“.
- Stufe 2: Nach dem Speichern prüft die Texterkennung jedes Bild. Bei einem Treffer wird der Eintrag sensibel und lokal und läuft ab. Der erkannte Text kommt in den verschlüsselten Suchtext.
- Nötig sind neue ClipStore-Funktionen, um die Sensibilität nachträglich zu setzen. Belege: `CopyPalCore/Content/ContentClassifier.swift:62-69`, `CopyPalServices/HistoryEngine.swift:73-91`.

**2 · Favoritennamen.** Ist ein Name gesetzt, zeigt `PopupRow` ihn als Titel (13 pt, `Theme.Notch.textPrimary`). Dahinter folgt die erste Inhaltszeile in `textSecondary`, abgeschnitten. VoiceOver liest „1: E-Mail privat, max@…“. Heute liest `App/History/ClipVisuals.swift:35-62` den Namen nie. `Docs/Testplaene/M6.md:18` erwartet ihn aber.

**3 · Bildschirmfotos wiederfinden.** Der Writer speichert heute CopyPal als Quelle (`App/Screenshot/ScreenshotResultWriter.swift:56-59`), obwohl `ScreenshotController.swift:606-614` die echte App schon kennt.
- Gespeichert werden sollen die App und der Fenstertitel. Die Zeile lautet dann „Bildschirmfoto · Safari – JIRA-1234 …“.
- Die Suche findet zusätzlich App-Namen und Typwörter (bild, screenshot, link, farbe). Treffer im Inhalt stehen vorne.
- Eine Schema-Änderung ist nicht nötig.

**4 · Bildschirmfreigabe.** `sharingType = .none` kommt auf Pop-up, Einfahr- und Toast-Panel (`App/Popup/PopupPanel.swift:69-86`), schaltbar unter Datenschutz, standardmäßig an.
- Weil Freigabe-Tools das nicht zuverlässig respektieren, kommt dazu der „Präsentationsmodus“ im Menü neben „Aufzeichnung pausieren“, optional über einen Fokus-Filter.
- In diesem Modus zeigen die Zeilen nur Nummer, Typ, App und Alter. Vorschaubilder sind aus. Der Modus endet nach 2 Stunden.
- Die Ergebnisse kommen als Tabelle in `Docs/Kompatibilitaet.md` (Zoom, Teams, Meet, FaceTime, OBS jeweils auf macOS 14, 15 und 26).

**5 · Bildschirmfotos von ignorierten Apps.** `ScreenshotResultWriter.swift:42-51` schreibt zuerst in die Zwischenablage und prüft erst danach Pause und Ignorierliste.
- Sofort (S): Berührt die Auswahl eine ignorierte App, wird mit `localOnly: true, concealed: true` geschrieben.
- Danach (M): Fenster ignorierter Apps werden schwarz gefüllt, Mitteilungsbanner ausgeblendet. Toast: „Bildschirmfoto kopiert · 1 Fenster geschwärzt“.

**6 · Vorschau mit →.** Die Taste → ist heute frei (`CopyPalCore/Input/PopupKeyMap.swift:76-77`). Sie ersetzt die Liste in derselben schwarzen Form durch den gewählten Eintrag: bis zu 12 Zeilen Text, die volle URL, das Bild mit Pixelmaß oder ein Farbfeld mit Hex-Wert.
- ↑/↓ blättern weiter, 1–8 und ↩ fügen wie gewohnt ein.
- Der Inhalt lädt erst beim Tastendruck und ist auf 4 KB begrenzt. Die Fenstergröße bleibt gleich, sensible Einträge bleiben maskiert.

**7 · Schwärzen.** Im Auswahl-Zustand schaltet eine Taste den Schwärzen-Modus ein.
- Ziehen zeichnet Balken, ein Klick entfernt einen, ⌫ entfernt den letzten.
- Bei ↩ wird massiv schwarz in die Bilddaten geschrieben, bevor PNG und TIFF entstehen. Weichzeichnen oder Verpixeln gibt es nicht.
- Mit #1 kommen Vorschläge über erkannten IBANs und Schlüsseln dazu, beschriftet „Vorschläge – bitte prüfen“.
- Version 1 gilt nur für Einzelaufnahmen und kommt erst nach dem M11-Handtest.

**8 · App-Regeln.** Eine Tabelle „App-Regeln“ unter Datenschutz ersetzt „Ignorierte Apps“ und die versteckte Liste für „⌘V halten aus“. Pro App gibt es drei Spalten:
- Aufzeichnen: Normal | Kurzlebig | Nie
- Einfügen: Wie kopiert | Immer ohne Formatierung
- ⌘V halten: An | Aus

„Kurzlebig“ heißt: lokal speichern, Ablauf nach 1 min bis Tagesende, gebaut auf der vorhandenen Ablauf-Logik. Das Schema sieht `app_rule` schon vor (`ROADMAP.md:192-195`).

**Zu entscheiden:**
- Die Taste → gehört entweder der Vorschau (#6) oder dem Umwandeln (#10). Empfehlung: Vorschau. Umwandeln kann später als Ebene in der Vorschau kommen.
- Wiederholtes ⌘V ist entweder die Warteschlange (#19) oder das „Durchblättern“ aus `ROADMAP.md:748`. Es braucht genau eine Bedeutung.
- Buchstabentasten im Overlay sollten nach Zeichen statt nach Tastencode zugeordnet werden, sonst passen sie auf AZERTY nicht.

## Bewusst nicht

- **KI- oder MCP-Zugriff auf den Verlauf:** gibt den entschlüsselten Verlauf an Agenten weiter und öffnet ihn für Prompt Injection.
- **Vorhersagende Sortierung:** bricht die festen Positionen 1–8, auf denen die ⌘V-Geste beruht.
- **Verlauf in Spotlight indizieren:** legt entschlüsselte Inhalte in einen Systemindex.
- **Textbausteine mit Abkürzungen:** erfordern das Mitlesen jeder Taste. Der Event-Tap reagiert bewusst nur auf ⌘V.
- **⌘C⌘C zum Zusammenführen:** ⌘C abzufangen bricht „⌘C funktioniert wie immer“.
- **Filter-Ketten und Schreibwerkzeuge im Verlauf:** zu viel Oberfläche. ⇧ = reine Form (#12) deckt den Großteil ab.
- **Cloud-Upload, Bildschirmvideo/GIF, Lineal, Farbpipette:** brauchen Netzwerk oder gehören in ein eigenes Screenshot-Tool.
- **Annotations-Editor (Pfeile, Rahmen, Text):** bräuchte eine zweite Akzentfarbe (`Docs/Design.md:67-70`) und vergrößert den Umfang stark. „In Vorschau öffnen“ mit Markup genügt.
- **Weichzeichnen oder Verpixeln:** lässt sich umkehren. Nur massives Schwärzen.
- **Geteilte Team-Pinboards:** brauchen Server und Konten.
- **Laufende Bildschirmfreigabe automatisch erkennen:** Es gibt keine öffentliche API dafür, und fremde Fenster abzufragen wäre Schnüffeln.
- **„Unsichtbar bei Bildschirmfreigabe“ versprechen:** `sharingType = .none` wirkt nicht zuverlässig.
- **`copypal://`-Links, die Inhalte liefern oder löschen:** Jede Webseite kann solche Links öffnen. Das gehört nur in App Intents.
- **Kurzbefehle dürfen den Verlauf standardmäßig lesen:** Ein geteilter Kurzbefehl könnte den Verlauf hochladen. Nur als Opt-in.

## Design-Review

### Hoch

**H1 · Berechtigungstext verspricht zu viel**
`App/Screenshot/ScreenshotPermissionWindow.swift:152`, `ScreenshotResultWriter.swift:42`
Problem: Bildschirmfotos landen ohne `.currentHostOnly` und unverschlüsselt in der Zwischenablage. Laut D15 gehen sie absichtlich an iPhone und iPad.
Fix: „Im Verlauf werden Bildschirmfotos verschlüsselt gespeichert; wie jede Kopie kann macOS sie per Universal Clipboard an dein iPhone oder iPad geben.“ Englisch entsprechend in `Localizable.xcstrings:1469`.

**H2 · Kürzel-Rekorder löst das andere Kürzel aus**
`App/Settings/SettingsWindow.swift:298-318`, `App/AppController.swift:238-260`
Problem: Beide Carbon-Kürzel bleiben aktiv, solange der Rekorder aufnimmt. ⌘⇧A öffnet dann das Overlay, ⌃⌥V das Pop-up. Der Hinweis „Schon … vergeben“ erscheint nie.
Fix: Während der Aufnahme `hotKey.register(nil)` und `screenshotHotKey.register(nil)`, danach `applyHotKey()`. Gesteuert über eine Closure `onRecordingChange` aus GeneralSettings.

**H3 · Pop-up ist für VoiceOver stumm**
`App/Popup/PopupController.swift:68-123, 164-176, 243-262, 287-293`
Problem: Öffnen, ↑/↓, Suchergebnisse und „Zu Favoriten hinzugefügt“ lösen keine Ansage aus.
Fix: Eine Methode `announce(_:)` wie in `ToastController.swift:27-31`. In `show()` gehört der Aufruf nach Zeile 103 und vor `guard animate` (Zeile 110), sonst fehlt die Ansage bei „Bewegung reduzieren“. ↑/↓ und Trefferzahl mit Priorität `.high`.

**H4 · Verlaufsfenster nicht per Tastatur bedienbar**
`App/History/HistoryWindow.swift:96-105, 285-287, 295-300`
Problem: Es gibt keine Auswahl. Kopieren geht nur per Doppelklick, alle anderen Aktionen nur über Hover oder Rechtsklick.
Fix:
- `List(selection:)` einführen.
- `.contextMenu(forSelectionType:menu:primaryAction:)` an die List hängen; das deckt ↩ und Doppelklick ab. `onTapGesture(count: 2)` entfernen.
- `.onDeleteCommand` für ⌫.
- Die Hover-Knöpfe auch bei Auswahl zeigen.
- Prüfen, ob die Zeilenfarben auf der blauen Auswahl lesbar bleiben.

**H5 · Nach der Freigabe startet die Aufnahme über den Systemeinstellungen**
`ScreenshotPermissionWindow.swift:128-139`, `App/Screenshot/ScreenshotController.swift:172-178, 189, 213`
Problem: `beginSession()` läuft eine Sekunde, bevor das Fenster schließt. Das eingefrorene Bild zeigt dann CopyPals eigenes Fenster, und als Quell-App gelten die Systemeinstellungen. Das betrifft vor allem den Weg nach Entzug oder erneuter Abfrage.
Fix: Den automatischen Start behalten, aber in anderer Reihenfolge: zuerst das Fenster schließen, dann die App wieder aktivieren, die beim ⌘⇧A vorne war, dann `beginSession()`. Zusätzlich die eigenen Fenster-IDs in `captureDisplay` ausschließen.

### Mittel

**M1 · Fenster geben den Fokus nicht zurück**
`SettingsWindow.swift:15-21`, `HistoryWindow.swift:22-28`, `ScreenshotPermissionWindow.swift:20-35`, `AppController.swift:173-181, 313-320`
Problem: Nach ⌘W, „Später“ oder „Abbrechen“ bleibt CopyPal ohne Fenster aktiv. Tastendrücke gehen ins Leere.
Fix: Vor `NSApp.activate()` die vorderste andere App merken. Beim Schließen sie wieder aktivieren, wenn kein anderes CopyPal-Fenster offen ist (oder `NSApp.hide(nil)`).

**M2 · Ein versehentliches ⌘⇧A führt in eine Sackgasse**
`App/Settings/AppSettings.swift:75`, `ScreenshotController.swift:100-104`, `ScreenshotPermissionWindow.swift:149-182`
Problem: Das Kürzel ist für alle aktiv und überdeckt ⌘⇧A in Finder und Chrome. Das Berechtigungsfenster nennt weder das Kürzel noch einen Weg, es zu ändern.
Fix: Hinweis „Geöffnet mit ⇧⌘A“ und ein SubtleButton „Kürzel ändern …“. Im Abschluss-Schritt des Onboardings eine Zeile: „⇧⌘A nimmt ein Bildschirmfoto auf – in den Einstellungen änderbar“.

**M3 · Kürzeltexte widersprechen der App**
`App/Onboarding/OnboardingWindow.swift:196, 279`, `App/Diagnostics/DiagnosticsView.swift:89`, `SettingsWindow.swift:202`
Problem: Das Onboarding verspricht „ohne neue Tastenkombinationen“. ⌃⌥V und ⌘⇧A sind fest im Text, und die Reihenfolge weicht vom Rekorder ab (⌘⇧A statt ⇧⌘A).
Fix: Den Slogan der Info-Seite als Willkommens-Untertitel nehmen. Kürzel per `KeyboardLayout.displayString(for:)` einsetzen und die xcstrings-Schlüssel anpassen. Im Text immer „Tastenkürzel“.

**M4 · Kürzelprüfung akzeptiert ⌘C, ⌘Z, ⌘Q**
`CopyPalCore/Input/HotKeyShortcut.swift:21-24`, `SettingsWindow.swift:309-311`
Problem: Ein Pop-up-Kürzel auf ⌘C würde das Kopieren in allen Apps kapern.
Fix: Eine Sperrliste in Core für ⌘ + C/X/V/Z/A/Q/W/H/M und ⇧⌘Z. Beim Ablehnen den Hinweis „Standardbefehl von macOS“ zeigen. Die CleanShot-Zeile in `Docs/Kompatibilitaet.md:90` am echten Mac prüfen.

**M5 · Hauptmenü ohne Widerrufen und ⌘,**
`App/MenuBar/MainMenu.swift:10-21`
Problem: ⌘Z wirkt in keinem Textfeld. ⌘, funktioniert nur bei offenem Statusmenü.
Fix: „Widerrufen“ (⌘Z), „Wiederholen“ (⇧⌘Z) und „Einstellungen …“ (⌘,) ergänzen. Die Closure kommt über `MainMenu.make`.

**M6 · Pause-Status ist falsch**
`SettingsWindow.swift:466-485`, `AppController.swift:163-171`
Problem: Die Zeile in den Einstellungen aktualisiert sich nicht. Nach Ablauf der Pause steht „Aufzeichnung läuft“ neben dem Knopf „Fortsetzen“.
Fix:
- Die Pause über `SettingsModel.pausedUntil` setzen.
- Ein einmaliger Timer zum Pausenende setzt `pausedUntil = nil` und ruft `statusItem.update()` auf (Zeitbasis `timeSource.now()`).
- Titel und Knopf aus `pausedUntil > now` ableiten.
- Im Pop-up eine feste Fußzeile „Aufzeichnung pausiert – im Menü fortsetzen“.

**M7 · Menüleistensymbol veraltet, falscher Tooltip**
`AppController.swift:106-111, 144-147`, `App/History/CaptureCoordinator.swift:92-98`, `App/MenuBar/StatusItemController.swift:39-43`
Problem: Das Warnsymbol erscheint bis zu 10 Minuten zu spät. Ein Speicherproblem heißt im Tooltip „Berechtigung fehlt“.
Fix: Ein Callback `onBlockedReasonChange` ruft `update()` auf. Für das Speicherproblem ein eigener Tooltip: „CopyPal – Verlauf nur vorübergehend“.

**M8 · „Aufzeichnung“ kollidiert mit „Bildschirmaufnahme“**
`StatusItemController.swift:41, 141-154`, `ScreenshotController.swift:595`
Problem: Auf Englisch steht „Pause Recording“ direkt neben „Allow Screen Recording …“.
Fix:
- EN: „Pause History“ und „History paused“.
- DE-Toast: „(Verlauf pausiert)“.
- „Bis zur Reaktivierung“ wird „Bis zum Fortsetzen“.
- Diagnose EN: „read the clipboard“.

**M9 · „Verlauf“ meint drei verschiedene Dinge**
`SettingsWindow.swift:145, 148, 178`, `OnboardingWindow.swift:198-199, 279`
Problem: Gemeint sind mal das Pop-up, mal das Verlaufsfenster, mal der Tab.
Fix: In Einstellungen und Onboarding für das Panel an der Notch „Pop-up“ verwenden („Pop-up mit Tastenkürzel öffnen“). Den Begriff im Onboarding einmal einführen. `PopupView.swift:191` bleibt, dort ist der Tab gemeint.

**M10 · „Geschafft!“ schon nach normalem ⌘V**
`OnboardingWindow.swift:82-84, 130-139`
Problem: Die Übung erkennt jedes der drei Beispiele als Erfolg, auch das, das ein einfaches ⌘V einfügt.
Fix: Nur `practiceText.contains(Self.samples[1])` zählen.

**M11 · Toasts verschweigen die halbe Auflösung**
`ScreenshotResultWriter.swift:27-42`, `ScreenshotController.swift:591, 599`
Problem: Auch die Zwischenablage bekommt das halbierte Bild, die Toasts sprechen aber nur vom Verlauf.
Fix: Zwei ehrliche Texte: „Bildschirmfoto kopiert – auf halbe Auflösung verkleinert“ und „… verkleinert kopiert – zu groß für den Verlauf“.

**M12 · Bildschirmfoto-Einstellungen stecken in „Allgemein“**
`SettingsWindow.swift:197-236`
Problem: Die Doku widerspricht sich (`Kompatibilitaet.md:89` gegen `Troubleshooting.md:89`). „Erteilt“ beruht nur auf dem Preflight.
Fix:
- Eine eigene Seite „Bildschirmfoto“ (camera.viewfinder) mit dem Zustand „Neustart nötig“.
- Statuszeilen für Bedienungshilfen und Zwischenablage unter „Allgemein“, beim Abschnitt „⌘V halten“.
- `Troubleshooting.md:89` anpassen.

**M13 · Toast an der Notch hat eckige obere Ecken**
`App/Notch/ToastController.swift:114-122`, `CopyPalCore/Layout/NotchGeometry.swift:78`
Problem: Der Toast ragt 30 pt über die Notch hinaus, ohne die geschwungenen Übergänge des Pop-ups (`Design.md:58`).
Fix: Mit Notch `NotchShape(bodyWidth: W − 2·flare, …, flare: PopupMetrics.flare)` und die Breite an das ToastModel geben. Ohne Notch bleibt die Kapsel.

**M14 · Toast umgeht die Notch-Tokens**
`ToastController.swift:110, 121`
Problem: Der Toast nutzt `.white` (100 %) und `Color.black` statt der Tokens.
Fix: `Theme.Notch.textPrimary` und `Theme.Notch.fill`. Keine gemeinsame Kapsel-Komponente bauen, wegen M13.

**M15 · Overlay: Das Loch springt, der Rahmen fliegt**
`App/Screenshot/ScreenshotOverlayPanel.swift:206-225, 256-269`
Problem: Die helle Aussparung springt sofort, der blaue Rahmen gleitet hinterher. Ein neuer Kandidat fliegt von der alten Position herein.
Fix: Nur animieren, wenn alter und neuer Kandidat existieren; das vor Zeile 206 prüfen. Dann `dimLayer.path` in derselben Animation setzen. Beim Wechsel von „kein Kandidat“ zu einem Rechteck ohne Animation.

**M16 · VoiceOver-Label einer Pop-up-Zeile unvollständig**
`App/Popup/PopupView.swift:280-282`
Problem: Typ-Tag, Favorit, Zeit und App fehlen. Ein Einmal-Code klingt nur wie „4: ••••••“.
Fix: Die Sensibilität vorne ins Label. In `.accessibilityValue`: Favorit, „formatiert“, „Vom iPhone“, Zeit, App.

**M17 · Overlay sagt Start, ⇥ und Status nicht an**
`CopyPalCore/Screenshot/SelectionStateMachine.swift:31-34, 245-254, 453-455`, `ScreenshotController.swift:256-264, 371-373, 627-630`
Problem: Auch die Warnung „Esc erneut verwirft N Abschnitte“ ist nur zu sehen, nicht zu hören.
Fix:
- Eine Methode `setStatus(_:)`, die auch Zeile 629 nutzt; dort `.needsAccessibility` vor der Ansage setzen.
- Nur bei Änderung ansagen, `.extending` und `.sections` überspringen, `.escArmed` mit `.high`.
- `hintText()` einmal beim Öffnen ansagen.
- ⇥ sagt die Art an (Fenster, Textblock).
- `setAccessibilityHelp` bei jedem Neuzeichnen.

**M18 · Kontrast von textSecondary im hellen Modus zu niedrig**
`App/DesignSystem/Theme.swift:12-13`
Problem: 4,49:1 auf `surface` (Seitenleiste der Einstellungen) und 4,34:1 auf Hover (Verlaufszeilen).
Fix: 0x73726E durch 0x6F6E6A ersetzen; das ergibt 5,10 / 4,76 / 4,60. `Design.md:10` und `:25` mit anpassen.

**M19 · Berechtigungswechsel ohne Ansage**
`ScreenshotPermissionWindow.swift:116-141`, `OnboardingWindow.swift:101-104, 159-169, 267-269`
Fix:
- „Erteilt“ ansagen, sobald sich der Zustand ändert.
- „Bildschirmaufnahme erteilt“ direkt bei `.granted` ansagen, noch vor Zeile 136.
- „Neustart nötig“ ansagen.
- Bei jedem Onboarding-Schritt „Schritt n von 6: Titel“ ansagen.

### Niedrig

- **N1 · Grünes „Erteilt“ bei fehlgeschlagener Prüfung** (`ScreenshotPermissionWindow.swift:163-164`). Fix: Eigener Fall `(.granted, .failed)` mit orangem Tag „Prüfung fehlgeschlagen“, ohne Knopf zu den Systemeinstellungen.
- **N2 · Berechtigungsfenster ohne Fußzeile wie im Onboarding** (`ScreenshotPermissionWindow.swift:177-187`). Fix: Inhalt, dann `Hairline()`, dann Fußzeile mit „Später“ rechts. `OnboardingView.width` statt 560.
- **N3 · Text ohne Theme-Farbe** (`OnboardingWindow.swift:223`, `ScreenshotPermissionWindow.swift:158`, `SettingsWindow.swift:508-515, 556-563`). Fix: `.foregroundStyle(Theme.Colors.textPrimary)`.
- **N4 · Symbolknöpfe in den Einstellungen: Farbe, Größe, Label** (`SettingsWindow.swift:567-573, 676-686, 720-727`; `PopupView.swift:153-165`). Fix: `IconButton` aus HistoryRow nach `Components.swift` verschieben (24×24, `contentShape`, textSecondary, deaktiviert textTertiary). Im Pop-up-Umschalter Padding 4. Label nach dem Muster „Nach oben: \<Name\>“.
- **N5 · PageHeader dreimal von Hand kopiert** (`HistoryWindow.swift:135-150`, `DiagnosticsView.swift:36-51`, `LabView.swift:67-82`). Fix: `PageHeader` verwenden und `PageHeader(verbatim:)` ergänzen.
- **N6 · Pop-up-Zeilen mischen Fenster- und Notch-Tokens** (`ClipVisuals.swift:195-264`). Fix: Ein Umgebungswert, der die Farbwelt festlegt.
- **N7 · Notch-Welt ohne Schrift- und Radius-Tokens** (`PopupView.swift:113-278`, `ScreenshotOverlayPanel.swift:98-113`). Fix: Die Werte benennen, nicht angleichen: Notch-Schriften 13/11/12 medium, `rowRadius = 8`, NSColor-Gegenstücke für das Overlay.
- **N8 · Hinweis-Kapsel springt um 17 pt** (`ScreenshotOverlayPanel.swift:314-322`). Fix: `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 43)` statt `.position`.
- **N9 · Schatten verschwindet beim Einfahren** (`PopupView.swift:22`, `PopupController.swift:423-430`). Fix: `shadowOpacity` im Modell von 0,28 im selben `withAnimation` auf 0 animieren.
- **N10 · „Bewegung reduzieren“ greift bei Größenänderungen nicht** (`PopupController.swift:272-274, 290-292`). Fix: `withAnimation(animates ? PopupMotion.resize : nil)`.
- **N11 · Suchhinweis mit 3,66:1** (`PopupView.swift:118-122`). Fix: `Theme.Notch.textSecondary` (7,37:1).
- **N12 · Kürzel-Rekorder ohne VoiceOver-Rückmeldung** (`SettingsWindow.swift:280-314`). Fix: Label „Tasten drücken …“ während der Aufnahme. Ansagen beim Start und beim Ablehnen.
- **N13 · Knopf heißt weiter „Anzeigen“, wenn der Inhalt sichtbar ist** (`HistoryWindow.swift:312`). Fix: `revealedText == nil ? "Anzeigen" : "Verbergen"`.
- **N14 · Von „Notch“ ist auch auf Macs ohne Notch die Rede** (`OnboardingWindow.swift:199`, `SettingsWindow.swift:145, 241, 244`). Fix: „oben am Bildschirm“. Im Onboarding die Notch nur nennen, wenn eine erkannt wird.
- **N15 · Favoritennamen gehen verloren** (`SettingsWindow.swift:605-608, 666-667`). Fix: Auch beim Fokusverlust und in `onDisappear` speichern. Untertitel „Benennen, sortieren, entfernen.“. Menüpunkte „Zu Favoriten hinzufügen“ und „Als nicht sensibel markieren“.
- **N16 · Fehler bleiben stumm** (`App/History/HistoryModel.swift:13-38`). Fix: Toast „Änderung nicht gespeichert“ und ein Log-Eintrag im catch.
- **N17 · Zwischenablage-Schritt im Onboarding vor macOS 15.4 ohne Funktion** (`OnboardingWindow.swift:55, 106-118`). Fix: Den Schritt bei `.unavailable` überspringen. Ab 15.4 einen Pfad-Hinweis wie in Zeile 230.
- **N18 · Plurale, Zahlenformat, Tastensymbole** (`HistoryWindow.swift:197`, `ScreenshotController.swift:842-882`, `SettingsWindow.swift:155`). Fix: Plural-Varianten im Katalog. `.formatted()` statt „0.30 s“. Einheitlich ↩ und esc, jeweils mit Verb. „Wird erweitert …“.
- **N19 · Statusmenü** (`StatusItemController.swift:59-61, 81-91, 117-133`). Fix: Das Kürzel nur anzeigen, wenn `hotKeyAvailable`. „Bedienungshilfen erlauben …“ statt „erneut erteilen“. „Bildschirmfoto aufnehmen“ in eine eigene Gruppe.

## Bereits umgesetzt (13.10.2026)

Direkt nach dem Review behoben, weil die Befunde den neuen Bildschirmfoto-Code betrafen:

- **H1:** Das Berechtigungsfenster verspricht nichts Falsches mehr: verschlüsselt im Verlauf, Weitergabe per Universal Clipboard wie jede Kopie.
- **H2:** Solange ein Kürzel-Rekorder aufnimmt, sind CopyPals eigene Kürzel abgemeldet. „Schon … vergeben“ erscheint jetzt wirklich.
- **H5:** Nach der Freigabe schließt erst das Fenster, die vorherige App kommt nach vorne, dann startet die Aufnahme.
- **M2 (Teil):** Das Berechtigungsfenster nennt das Kürzel und hat „Kürzel ändern …“.
- **M4:** ⌘C, ⌘X, ⌘V, ⌘Z, ⌘A, ⌘Q, ⌘W, ⌘H, ⌘M, ⌘⇥, ⌘Leertaste und ⇧⌘Z werden als Kürzel abgelehnt (nach dem Zeichen im aktuellen Layout).
- **M11:** Die Toasts sagen, wenn auch die Zwischenablage nur die halbe Auflösung bekommt.
- **M15, N8:** Rahmen und Aussparung gleiten gemeinsam; die Hinweiszeile springt nicht mehr.
- **M17, M19 (Teil):** VoiceOver hört den Hinweis beim Öffnen, wichtige Statuszeilen („Esc erneut verwirft …“ mit hoher Priorität) und „Bildschirmaufnahme erteilt“.
- **N1, N2, N12 (Teil):** Eigener Zustand „Prüfung fehlgeschlagen“; Fußzeile wie im Onboarding; der Rekorder heißt für VoiceOver „Tasten drücken …“, solange er aufnimmt.
- **Idee #5 (erster Teil):** Liegt ein Fenster einer ignorierten App in der Auswahl (Mitte oder Ecke), geht das Bild nur auf diesem Mac in die Zwischenablage, als verborgen markiert und nicht in den Verlauf.
- **Idee #3 (Teil):** Bildschirmfotos tragen im Verlauf die aufgenommene App als Quelle statt CopyPal.

Alles andere in diesem Bericht ist offen und wartet auf deine Entscheidung.

## Vorschlag für die nächsten Schritte

1. **Hoch-Befunde beheben**, meist Aufwand S: H1 Berechtigungstext, H2 Kürzel-Rekorder, H5 Startreihenfolge. Dazu M1 (Fokus zurückgeben) und M10 (Übungsschritt).
2. **Barrierefreiheit in einem Durchgang:** H3, H4, M16–M19, N10, N11.
3. **Texte und Notch-Form:** M2, M3, M8, M9 (Begriffe und Kürzel), M6, M7 (Pause und Menüsymbol), M13, M14 (Toast), N18.
4. **Schnelle Erweiterungen (S):**
   - Bildschirmfotos von ignorierten Apps nur lokal schreiben (#5, erster Teil).
   - Favoritennamen im Pop-up (#2).
   - Bildschirmfotos mit Quell-App und Fenstertitel (#3).
   - `sharingType = .none` samt Testtabelle (#4, erster Teil).
   - Abschnitt „Bewusst nicht“ in der ROADMAP (#16).
5. **Den M11-Handtest abschließen, dann die Texterkennung (#1):** zuerst ⇧⏎ als Text, dann die Prüfung auf sensible Inhalte und die Suche in Bildern. Danach Schwärzen (#7) auf derselben Grundlage.
6. **Die Taste → festlegen**, dann Vorschau (#6) und Präsentationsmodus (#4, zweiter Teil) bauen. Danach App-Regeln (#8).

## Umsetzungsplan (18.10.2026)

Auftrag: die fünf wichtigsten Erweiterungen umsetzen, weitere Ideen prüfen und nur das bauen, was CopyPal für Nutzer rund macht. Jedes Paket geht einzeln durch die CI (Linux-Tests, macOS-Build ohne Warnungen, Selbsttest).

**Neu dazugekommen (eigene Ideen):**
- **Kürzel-Karte unter dem Menüleisten-Symbol** – schon umgesetzt.
- **Bildschirmfoto als Datei (⌘S im Overlay):** legt ein PNG dort ab, wo macOS auch seine Bildschirmfotos ablegt (Standard: Schreibtisch). Wer eine Datei braucht, muss sonst den Umweg über Vorschau gehen.
- **„Letzte Kopie vergessen“ im Menü:** löscht den neuesten Eintrag und leert die Zwischenablage, wenn sie ihn noch hält – für das versehentlich kopierte Passwort aus einer App ohne Markierung.
- **Restzeit sensibler Einträge:** Die Zeile zeigt „noch 42 s“, die Fußzeile „⌘P behalten“. Erklärt, warum Einträge verschwinden (Idee #11).
- **Saubere Links beim Einfügen ohne Formatierung (⇧):** entfernt utm_*, fbclid, gclid und ähnliche Parameter (Idee #12), abschaltbar unter Datenschutz.
- **Favoriten anlegen:** „Neuer Favorit …“ auf der Seite Favoriten – Textvorlagen ohne Umweg über die Zwischenablage (Idee #18).

**Pakete:**

| Paket | Inhalt |
|---|---|
| P1 | Favoritennamen im Pop-up (#2) · Bildschirmfotos mit App und Fenstertitel, Suche nach App und Typ (#3) · Restzeit sensibler Einträge · saubere Links · „Letzte Kopie vergessen“ |
| P2 | Pop-up aus Bildschirmfreigaben heraushalten, Präsentationsmodus (#4) |
| P3 | Vorschau mit → im Pop-up (#6) |
| P4 | Texterkennung: ⇧⏎ kopiert Text, Bilder werden durchsuchbar und auf Sensibles geprüft (#1) |
| P5 | Fenster geben den Fokus zurück (M1) · VoiceOver im Pop-up (H3) · Bildschirmfoto als Datei (⌘S) · Favoriten anlegen |

**Bewusst noch nicht:** Das Verlaufsfenster per Tastatur (H4) braucht eine eigene Auswahl-Logik mit lesbaren Farben auf der Systemauswahl; das lässt sich nur am Mac sauber abstimmen. App-Regeln (#8) und Automation (#9) brauchen eigene Entscheidungen zu Datenschutz und Oberfläche. Umwandeln (#10) und Sammeln (#19) konkurrieren um → und wiederholtes ⌘V. Schwärzen (#7) kommt nach der Texterkennung. Ergebnis-Kapsel (#20), Selbstauslöser (#15), Schweben (#21) und seitliches Erweitern (#22) sind Nischen.
