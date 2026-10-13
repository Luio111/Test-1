# CopyPal – Umsetzungsplan (Mac-Version)

Stand: 12.10.2026 · Zielplattform: macOS 14 Sonoma und neuer · Vertrieb: direkt (außerhalb des App Stores), Preismodell noch offen.

CopyPal ist ein nativer Clipboard-Manager für den Mac:

- **⌘C** funktioniert wie immer.
- **⌘V kurz tippen** fügt wie gewohnt den letzten Eintrag ein.
- **⌘V halten** öffnet ein Pop-up aus der Notch mit den letzten 8 Einträgen.

Schwerpunkte sind Datenschutz und Einfachheit. Die iPhone-App ist ausdrücklich **nicht** Teil dieses Plans. Das Datenmodell ist aber so angelegt, dass eine spätere iCloud-Synchronisierung ohne Umbau möglich ist.

---

## 0. Auf einen Blick

### Statusübersicht

| Meilenstein | Inhalt | Status |
|---|---|---|
| M0 | Fundament: Projekt, Signierung, CI, Diagnose | erledigt (12.10.2026) |
| M1 | Spike A: ⌘V halten, Einfügen, Fokus | umgesetzt, CI-Selbsttest grün · Handtest offen |
| M2 | Spike B: Zwischenablage, Datenschutz-Abfragen, Universal Clipboard | umgesetzt, CI-Selbsttest · Handtest offen (Passwortmanager, iPhone, `accessBehavior`) |
| G1 | Go/No-Go-Entscheidung | wartet auf die Handtests M1/M2 |
| M3 | Kern und Speicher (parallel zu M1/M2) | umgesetzt, CI grün · Schlüsselbund-Test lokal offen |
| M4 | Alpha: echter Verlauf und Pop-up, Alltagsnutzung | umgesetzt, CI-Selbsttest · Alltagsnutzung offen |
| G2 | Rückblick nach einer Woche Alltagsnutzung | offen |
| M5 | Datenschutz komplett | umgesetzt, Korpus 0 Fehler · Handtest offen |
| M6 | Vorschauen und Favoriten | umgesetzt · Handtest offen |
| M7 | Notch-Erlebnis, Onboarding, Einstellungen | umgesetzt (Deutsch + Englisch) · Handtest offen |
| M8 | Härtung, Performance, Kompatibilität | umgesetzt, soweit automatisierbar · CI-Selbsttest auf macOS 14.8 und 15.7 grün · Messungen am Mac, Matrix offen |
| G3 | Bereit für die Beta | offen (D8, D10–D12) |
| M9 | Beta-Vertrieb: Developer ID, Notarisierung, Sparkle | vorbereitet (Sparkle, `scripts/release.sh`, Anleitungen) · braucht Developer-Account (D10) |
| M10 | Release 1.0 | vorbereitet (Website, Rechtstexte als Vorlage, Checkliste) · braucht D11 und deine Angaben |

### Reihenfolge (schwierigste Risiken zuerst)

```
M0 Fundament ─► M1 Spike A: ⌘V halten ─► M2 Spike B: Zwischenablage ─► [G1 Go/No-Go]
                M3 Kern & Speicher (parallel, über CI geprüft) ─────────────┘
─► M4 Alpha (tägliche Nutzung) ─► [G2] ─► M5 Datenschutz ─► M6 Vorschauen & Favoriten
─► M7 Notch-UI, Onboarding, Einstellungen ─► M8 Härtung ─► [G3] ─► M9 Beta ─► M10 Release 1.0
```

### Leitprinzipien

- **Die größten Unbekannten zuerst.** Zuerst werden diese Fragen geklärt:
  - Funktioniert das Abfangen von ⌘V zuverlässig?
  - Wie viel Verzögerung entsteht dabei?
  - Bleibt der Fokus in der richtigen App?
  - Lässt macOS das Mitlesen der Zwischenablage zu?

  Erst danach entsteht Feinschliff.
- **Der Spike ist kein Wegwerfcode.** Zustandsautomat, Event-Tap, Layout-Erkennung und Tastensynthese werden gleich produktionsreif gebaut. Nur das „Labor“-Fenster (nur im Debug-Build) ist reines Messwerkzeug.
- **Alles, was ohne Mac prüfbar ist, liegt im Swift-Package `CopyPalKit`** und läuft bei jedem PR in der CI. So kann Claude Compile- und Testfehler selbst sehen und beheben.
- **Datenschutz ist Standard, keine Option.** Verschlüsselt wird ab dem ersten gespeicherten Byte. Markierungen von Passwortmanagern werden ab M2 beachtet.

---

## 1. Architektur

### 1.1 Repository-Struktur

```
Test-1/
├─ .github/
│  ├─ workflows/copypal-ci.yml           # muss im Repo-Root liegen
│  └─ pull_request_template.md           # Ziel · Änderungen · So testen · Bekannte Grenzen
└─ CopyPal/
   ├─ project.yml                        # XcodeGen; CopyPal.xcodeproj wird NIE eingecheckt
   ├─ .gitignore                         # *.xcodeproj, DerivedData, .build, Signing.local.xcconfig
   ├─ Config/
   │  ├─ Base.xcconfig                   # macOS 14.0, Signierung, Hardened Runtime, Swift-Modus (ADR 0002)
   │  ├─ Debug.xcconfig / Release.xcconfig
   │  └─ Signing.local.xcconfig.example  # DEVELOPMENT_TEAM, BUNDLE_ID_PREFIX (Kopie bleibt lokal)
   ├─ App/                               # dünnes UI-Target (AppKit-Lifecycle + SwiftUI-Inhalte)
   │  ├─ CopyPalMain.swift, AppDelegate.swift, AppInfo.swift
   │  ├─ MenuBar/      StatusItemController, MainMenu (unsichtbar, für ⌘-Kurzbefehle)
   │  ├─ DesignSystem/ Theme (Tokens), Components
   │  ├─ Popup/        PopupPanel, PopupController, PopupViewModel, PopupView, ClipRowView
   │  ├─ Notch/        ScreenLocator, NotchAnimator, CopyFeedbackController
   │  ├─ Onboarding/   OnboardingWindowController + Schritt-Views
   │  ├─ Settings/     SettingsWindowController + Allgemein/Verlauf/Datenschutz/Favoriten/Über
   │  ├─ Diagnostics/  DiagnosticsModel, DiagnosticsView, DiagnosticsWindowController, Lab/ (nur #if DEBUG)
   │  ├─ Licensing/    LicenseProvider.swift (v1: AlwaysLicensed)
   │  └─ Resources/    Assets.xcassets, Localizable.xcstrings (ab der zweiten Sprache, D9)
   ├─ Packages/CopyPalKit/
   │  ├─ Package.swift
   │  ├─ Sources/CopyPalCore/      # nur Foundation, plattformneutral (u. a. DiagnosticsReport)
   │  ├─ Sources/CopyPalStorage/   # GRDB, CryptoKit, Keychain
   │  ├─ Sources/CopyPalSystem/    # AppKit-, CoreGraphics- und Carbon-Adapter
   │  ├─ Sources/CopyPalServices/  # Orchestrierung: Erfassen, Verlauf, Einfügen
   │  └─ Tests/                    # je Modul ein Testtarget
   ├─ scripts/  bootstrap.sh, reset-dev-state.sh, ci-check-warnings.sh, release.sh (ab M9)
   └─ Docs/     ROADMAP.md, ADR/, Testplaene/M0.md…M10.md, Kompatibilitaet.md,
                Troubleshooting.md, Release-Checkliste.md
```

### 1.2 Module

| Modul | Inhalt | Hängt ab von | Getestet |
|---|---|---|---|
| **CopyPalCore** | Datenmodell · Zustandsautomat der Halte-Geste · Inhaltserkennung (Text, Link, Farbe, Bild, Datei) · Erkennung sensibler Inhalte (IBAN, Kartennummern, API-Keys) · Pasteboard-Markierungen · Standard-Ignore-Liste · Fingerprint/Duplikate · Verlaufsregeln · Suche · Notch-Geometrie · `Clock` | Foundation | CI |
| **CopyPalStorage** | SQLite über GRDB (WAL, Migrationen) · Repository · Blob-Ablage · Verschlüsselung (AES-GCM) · Schlüssel in der Keychain · Aufräumen | Core, GRDB, CryptoKit, Security | CI; Keychain-Test lokal |
| **CopyPalSystem** | Event-Tap (eigener Thread) · Tastaturlayout-Erkennung · ⌘V-Synthese · Secure-Input-Erkennung · Zwischenablage lesen/schreiben/überwachen · Pasteboard-Freigabe (`accessBehavior`) · Bedienungshilfen-Status · vordere App, fokussiertes Fenster, App-Icons | Core, AppKit, CoreGraphics, Carbon | CI (Fakes, private Pasteboards) + manuell |
| **CopyPalServices** | Erfassen · Datenschutz-Filter · Verlauf · Einfügen · Aufbewahrung/Ablauf · Miniaturen | Core, Storage, System (über Protokolle) | CI mit Fakes |
| **App** | Verdrahtung, Menüleiste, Pop-up, Notch-Animation, Onboarding, Einstellungen, Diagnose, Sparkle | alles + KeyboardShortcuts, Sparkle | manuell |

**Testnähte (Protokolle):** `Clock`, `PasteboardProtocol`, `EventPosting`, `KeyStore`, `FrontmostAppProviding`, `ScreenProviding`.

### 1.3 Ablauf zur Laufzeit

**Erfassen**
```
PasteboardMonitor (alle 0,4 s, vergleicht nur changeCount)
 → zuerst nur die Typen lesen:
     · Passwortmanager-Markierung (Concealed/Transient/AutoGenerated) → verwerfen, keine Daten lesen
     · com.apple.is-remote-clipboard → als „vom iPhone“ markieren, Daten erst bei Bedarf lesen (D3)
     · sonst Daten im Hintergrund mit Timeout lesen
 → Datenschutz-Filter: Ignore-Liste · Pause · eigener Schreibvorgang (nur nach oben rücken)
 → Inhaltserkennung + Erkennung sensibler Inhalte
 → Verlauf: identisch mit oberstem Eintrag → nichts tun · identisch mit älterem → nach oben · sonst neu
 → verschlüsselt speichern → Pop-up-Daten aktualisieren → „Kopiert ✓“
```

**Einfügen**
```
Event-Tap → Zustandsautomat
 ├─ kurz getippt → ⌘V wird beim Loslassen synthetisiert (normales Einfügen)
 └─ gehalten     → Pop-up erscheint (Panel ist vorgewärmt)
                    → Auswahl N → Eintrag in die Zwischenablage
                       (normal | sensibel: nur auf diesem Mac + Concealed-Markierung)
                    → Pop-up schließen → kurz warten → prüfen, ob die Ziel-App noch vorne ist
                    → ⌘V synthetisieren → Eintrag N rückt nach oben
```

### 1.4 Grundsatzentscheidungen (je als kurzes ADR in `Docs/ADR/`)

1. **AppKit-Lifecycle** (NSApplicationDelegate, NSStatusItem, eigene Fenster-Controller); SwiftUI nur für Inhalte. So gibt es volle Kontrolle über Panel, Fensterebenen und Aktivierung.
2. **XcodeGen und ein lokales SPM-Package.** Claude schreibt nur `project.yml` und `.swift`-Dateien. Die Xcode-Projektdatei erzeugt `xcodegen` auf dem Mac.
3. **Keine Sandbox, Hardened Runtime an.** Der aktive Event-Tap und die synthetischen Tasten brauchen die Bedienungshilfen-Freigabe.
4. **Event-Tap auf eigenem Thread.** Der Callback ist minimal: keine Allokation, kein IO. UI-Aktionen laufen auf dem Main-Thread.
5. **Speicher: GRDB (SQLite) plus verschlüsselte Blob-Dateien** statt SwiftData (Begründung in 1.5).
6. **Swift-Sprachmodus (ADR 0002).** Swift 6 für Core, Storage und Services. System und App vorerst Swift 5 mit vollständiger Concurrency-Prüfung und explizitem `@MainActor`; Warnungen lassen die CI scheitern. Umstellung auf Swift 6 spätestens in M8.
7. **Tests mit Swift Testing.**
8. **Wenige Abhängigkeiten:** GRDB, KeyboardShortcuts (Fallback-Hotkey), ab M9 Sparkle. Keine Analytics, kein Crash-SDK.
9. **Alle UI-Texte ab Tag 1 lokalisierbar** (`LocalizedStringKey`, `String(localized:)`). Der String Catalog kommt mit der zweiten Sprache (D9) dazu, Englisch braucht dann keinen Umbau.
10. **Lizenz-Schnittstelle `LicenseProvider`:** in v1 immer „lizenziert“. So bleibt das Preismodell offen.
11. **Getrennte Bundle-IDs:** Debug `<prefix>.CopyPal.dev`, Release `<prefix>.CopyPal`. Das trennt Freigaben, Keychain und Daten.
12. **Kein Wiederherstellen der alten Zwischenablage nach dem Einfügen.** Der eingefügte Eintrag bleibt oben. Damit gilt „⌘V = zuletzt gewählter Eintrag“, und das iPhone bekommt über Universal Clipboard genau diesen Eintrag.

### 1.5 Speicher: GRDB statt SwiftData

**Warum GRDB:**
- Mit GRDB lässt sich genau festlegen, welche Felder und Blobs verschlüsselt werden. SwiftData kann das nicht, der Store läge im Klartext.
- Für die spätere iCloud-Synchronisierung funktioniert CKSyncEngine mit jedem Speicher. Die automatische CloudKit-Anbindung von SwiftData schränkt das Schema ein und synchronisiert ungesteuert. Sensible Einträge dürfen aber nie hochgeladen werden.
- SwiftData ist unter macOS 14 noch unausgereift.
- GRDB läuft in `swift test` auf der CI.

**Verschlüsselung:**
- **Schlüssel:** 256 Bit, einmal erzeugt, in der Keychain abgelegt (nur dieses Gerät, nicht synchronisiert).
- **Verfahren:** AES-GCM über CryptoKit, mit der Datensatz-ID als zusätzlichen Daten (AAD).
- **Verschlüsselt:** alle Inhalte, Vorschauen und Miniaturen.
- **Im Klartext:** nur IDs, Zeitstempel, Typ, Flags, Größen und die Bundle-ID der Quell-App.
- **Duplikaterkennung:** über einen HMAC-Fingerprint, also keinen erratbaren Klartext-Hash.
- **Suche:** läuft im Arbeitsspeicher über die entschlüsselten Vorschauen. Sensible Einträge sind nicht durchsuchbar.
- **Schlüssel verloren** (z. B. nach einem Wechsel des Signierteams): Datenordner beiseite verschieben, frisch starten, Hinweis anzeigen. Kein Absturz.
- **Ablageorte:**
  - Datenbank und Blobs: `~/Library/Application Support/<bundle-id>/`
  - Miniaturen (ebenfalls verschlüsselt): `~/Library/Caches/<bundle-id>/Thumbnails/`

### 1.6 Datenmodell (Schema v1, sync-tauglich)

**Tabelle `clip_item`**

| Feld | Zweck |
|---|---|
| `id` (UUID) | in der App erzeugt, für späteren Sync geeignet |
| `created_at`, `last_used_at`, `modified_at` | Sortierung nach `last_used_at`; `modified_at` für späteren Sync |
| `deleted_at` | Löschmarke (Tombstone) |
| `kind` | text, richText, link, color, image, files, other |
| `fingerprint` | HMAC zur Duplikaterkennung; Index, aber ohne UNIQUE |
| `preview_enc` | verschlüsselte Vorschau (Zeilen, Host, Farbwert, Dateinamen, Bildmaße) |
| `source_bundle_id` | Quell-App |
| `origin` | `local` oder `remoteDevice` (vom iPhone) |
| `sensitivity`, `expires_at` | Art des sensiblen Inhalts (IBAN, Karte, Geheimnis, Einmalcode) und Ablaufzeitpunkt |
| `local_only` | wird nie synchronisiert (sensible Einträge und iPhone-Einträge) |
| `pinned_at`, `pin_label`, `pin_sort` | Favoriten |
| `byte_size`, `use_count` | Größe und Nutzungszähler |

**Weitere Tabellen**
- `clip_representation`: die einzelnen Pasteboard-Repräsentationen eines Eintrags (UTI, inline oder als Blob, verschlüsselt). Sie sind unveränderlich.
- `app_rule`: pro App „ignorieren“ oder „Halten aus“.
- `meta`: Schlüssel/Wert-Paare, z. B. die letzte Bereinigung und später der Sync-Zustand.

**Regeln für späteren Sync**
- Nur UUIDs als Schlüssel.
- Löschen über Löschmarken.
- Duplikate werden im Code erkannt, nicht über die Datenbank.
- `local_only` wird immer respektiert.

### 1.7 Zustandsautomat der Halte-Geste (rein, vollständig unit-getestet)

**Was zählt als ⌘V:**
- Es ist genau ⌘ gedrückt, also nicht zusätzlich ⇧, ⌥ oder ⌃.
- Die Taste erzeugt mit ⌘ im aktuellen Tastaturlayout ein „v“.
- Selbst erzeugte Events tragen eine Markierung und werden immer durchgelassen.

| Zustand | Ereignis | Aktion | Neuer Zustand |
|---|---|---|---|
| bereit | ⌘V gedrückt (keine Wiederholung, nicht von uns, App nicht auf „Halten aus“) | Event schlucken, Timer starten | wartend |
| bereit | alles andere (auch ⌘⇧V, ⌥⌘V) | durchlassen | bereit |
| wartend | V-Wiederholung | schlucken | wartend |
| wartend | V losgelassen vor der Schwelle | schlucken, ⌘V synthetisieren | bereit |
| wartend | Schwelle erreicht | Pop-up zeigen | gehalten |
| wartend | ⌘ losgelassen | durchlassen | wartend (das Loslassen von V entscheidet) |
| wartend | andere Taste gedrückt | ⌘V synthetisieren, dann die Taste durchlassen | bereit |
| gehalten | V-Wiederholung oder V losgelassen | schlucken | gehalten |
| gehalten | Pop-up geschlossen | – | bereit |
| beliebig | Tap von macOS deaktiviert (Timeout) | wieder einschalten, Zustand verwerfen | bereit |

### 1.8 Tasten im Pop-up

| Taste | Suchfeld leer | Suchtext vorhanden |
|---|---|---|
| 1–8 (auch mit noch gehaltenem ⌘) | Eintrag N einfügen | Ziffer kommt ins Suchfeld |
| ⇧ + 1–8 | N als reinen Text einfügen | – |
| ⌘1–8 / ⌘⇧1–8 | N einfügen / als Text einfügen | N einfügen / als Text einfügen |
| ↑ ↓, ↩, ⇧↩ | auswählen, einfügen, als Text einfügen | genauso |
| Buchstaben, ⌫ | Suche starten bzw. bearbeiten | genauso |
| ⇥ | zwischen Verlauf und Favoriten wechseln | genauso |
| ⌘P, ⌘⌫ | anpinnen bzw. lösen, Eintrag löschen | genauso |
| Esc | schließen | Suche leeren; zweites Esc schließt |

Ziffern werden über die physische Taste erkannt, nicht über das erzeugte Zeichen. So funktioniert ⇧+Zahl auch auf QWERTZ und AZERTY.

---

## 2. Zusammenarbeit und Werkzeuge

### 2.1 Ablauf pro PR

1. **Claude:** kleiner PR mit einem Thema, wenn möglich unter 400 Zeilen. Die Beschreibung enthält eine „So testen“-Checkliste aus `Docs/Testplaene/M<N>.md`.
2. **CI muss grün sein.** Fehler liest und behebt Claude selbst über die GitHub-Anbindung, bevor du testest. Du bekommst nur grüne PRs.
3. **Du:**
   1. PR-Branch holen: `git fetch origin && git switch <branch>` (der Branch steht im PR)
   2. `./scripts/bootstrap.sh`
   3. in Xcode ⌘R
   4. Checkliste abhaken
   5. Ergebnis und Diagnose-Bericht als PR-Kommentar posten
4. **Merge nach dem Handtest.** Bei PRs, die nur das Package ändern, reicht die CI.
5. **Fehler als GitHub-Issue** mit Diagnose-Bericht.

### 2.2 CI (`.github/workflows/copypal-ci.yml`)

- **Auslöser:** Pull Requests und Push auf `main`, nur bei Änderungen unter `CopyPal/**`. Ältere Läufe desselben Branches werden abgebrochen.
- **Schritte:**
  1. Linux: `swift test` im Package (günstig, läuft zuerst)
  2. macOS (nur wenn 1 grün): `swift test`, `xcodegen generate`, `xcodebuild build` ohne Signierung
  3. Compiler-Warnungen im eigenen Code lassen den Lauf scheitern (`scripts/ci-check-warnings.sh`)
- **Versionen fest:** Xcode 26.0 (wie der Entwicklungs-Mac) und XcodeGen 2.46.0. Mindestversion laut README: Xcode 16.3.
- **Keychain-Tests** laufen nur lokal.
- **Kosten:** In privaten Repos zählen macOS-Minuten mit Faktor 10 gegen das Freikontingent. Ziel sind unter 8 Minuten pro Lauf. Öffentliche Repos sind kostenlos (siehe D1).
- **Optional:** Swift-Toolchain im Cloud-Container über einen SessionStart-Hook. Dann laufen die Core-Tests schon vor dem Push.

### 2.3 Signierung während der Entwicklung (ohne bezahlten Developer-Account)

- **Kostenloses „Personal Team“ in Xcode einrichten:** Xcode → Settings… → Accounts → Apple ID hinzufügen, dann unter Manage Certificates… ein „Apple Development“-Zertifikat anlegen.
- **`Config/Signing.local.xcconfig`:** legt `scripts/bootstrap.sh` an und trägt die Team-ID ein, wenn sie eindeutig ist; `BUNDLE_ID_PREFIX` z. B. `io.github.<name>`.
- **Immer mit „Apple Development“ signieren, nie „Sign to Run Locally“.** macOS bindet die Bedienungshilfen-Freigabe an die Signatur. Mit Ad-hoc-Signatur ginge sie bei jedem Build verloren.
- **Beim späteren Wechsel zum bezahlten Team (M9):** Die Freigabe muss einmal neu erteilt werden. Die Entwicklungsdaten werden verworfen. Das ist erwartet.

---

## 3. Meilensteine

### M0: Fundament und Werkzeugkette

**Ziel:** ein leeres, korrekt signiertes Menüleisten-App-Gerüst, das bei dir und in der CI baut. Dazu ein früher Beweis, dass die Bedienungshilfen-Freigabe Rebuilds übersteht, und ein erster Blick auf die Pasteboard-Freigabe.

**Aufgaben**
- **PR 0.1:**
  - `project.yml`: Menüleisten-App ohne Dock-Icon (`LSUIElement`), Mindestversion 14.0, Hardened Runtime, zwei Bundle-IDs
  - `Config/*.xcconfig`, `.gitignore`
  - `scripts/bootstrap.sh`: prüft XcodeGen, legt die Signing-Datei an, erzeugt das Projekt
  - `Package.swift` mit 4 Modulen und Platzhaltertests
  - App-Gerüst mit Menüleisten-Icon, Menü „Diagnose…“ und „Beenden“
- **PR 0.2:** CI-Workflow, PR-Vorlage, `Docs/Troubleshooting.md`, `Docs/Testplaene/M0.md`, `scripts/reset-dev-state.sh`. Dieses Dokument liegt bereits als `Docs/ROADMAP.md` vor.
- **PR 0.3: Diagnose-Fenster.** Es zeigt:
  - macOS- und App-Version, Bundle-ID
  - Team-ID der Signatur
  - Status der Bedienungshilfen, mit Knopf zum Anfragen
  - `NSPasteboard.accessBehavior` (macOS 15.4+), dazu Testlesen von `changeCount` und `types`
  - Knopf „Bericht kopieren“

**Fertig wenn**
- [ ] Der CI-Lauf im PR ist grün.
- [ ] Nach `./scripts/bootstrap.sh` und ⌘R in Xcode erscheint ein Icon in der Menüleiste, ohne Dock-Icon und ohne Fenster.
- [ ] `codesign -dv --verbose=4 <App>` zeigt `Authority=Apple Development: …` und deine Team-ID.
- [ ] Die Bedienungshilfen sind freigegeben. Die Freigabe besteht nach Codeänderung und neuem Build weiter.
- [ ] Die Diagnose zeigt den `accessBehavior`-Wert und ob das Lesen der Typen ohne Systemdialog klappt. Das Ergebnis steht im PR.
- [ ] `swift test` in `Packages/CopyPalKit` ist lokal grün.

---

### M1: Spike A – ⌘V halten, Einfügen, Fokus (höchstes Risiko)

**Ziel:** beweisen, dass die Kerninteraktion zuverlässig und schnell genug ist. Dazu die Parameter festlegen: Halteschwelle, Wartezeit vor dem Einfügen und Weg der Tasteneingabe ins Pop-up.

**Aufgaben**
- **PR 1.1 (nur CI):** Zustandsautomat aus 1.7 mit mehr als 20 Szenario-Tests.
- **PR 1.2: Event-Tap ohne Pop-up.** Jedes ⌘V wird geschluckt und neu erzeugt.
  - Tap auf eigenem Thread; wird wieder eingeschaltet, wenn macOS ihn wegen Timeout deaktiviert
  - Wächter, der den Tap sofort entfernt, wenn die Freigabe entzogen wird
  - Tastaturlayout-Erkennung mit ⌘ als Modifier (auch „Dvorak – QWERTY ⌘“), aktualisiert bei Layoutwechsel
  - ⌘V-Synthese mit Markierung
  - Erkennung von Secure Input (Passwortfelder) samt verursachender App
  - Ablauf für die Bedienungshilfen-Freigabe: anfragen, Systemeinstellungen öffnen, Status abfragen
- **PR 1.3: Halten-Pfad.**
  - Nicht aktivierendes Panel (Fokus bleibt in der Ziel-App). Es wird beim Start angelegt und versteckt.
  - Testinhalt mit 8 Dummy-Einträgen; Eintrag 1 ist formatierter Text.
  - Labor-Fenster (nur Debug) mit:
    - Status von Tap, Freigabe und Secure Input
    - erkanntem Layout
    - Schwellen-Regler (0,15–0,6 s)
    - Event-Log
    - Messung der Tipp-Dauer (= Zusatzverzögerung) und der Pop-up-Latenz
- **PR 1.4:** Korrekturen aus Runde 1 der Kompatibilitätsmatrix.

**Technische Festlegungen**
- **Nach der Auswahl im Pop-up:** Panel schließen, kurz warten (Start 30 ms, wird gemessen) und prüfen, ob die Ziel-App noch vorne ist. Nur dann ⌘V posten, sonst nur in die Zwischenablage legen und einen Hinweis zeigen.
- **Hält der Nutzer ⇧ noch gedrückt,** soll die Ziel-App trotzdem ⌘V sehen, nicht ⌘⇧V.
- **Falls das Panel den Fokus nicht sauber zurückgibt:** Ersatzweg, bei dem der Tap die Tasten selbst ans Pop-up weiterleitet (D4).

**Fertig wenn**
- [ ] 50 Mal kurz ⌘V in TextEdit: jedes Mal genau eine Einfügung. Die Tipp-Dauer (Median) ist notiert und fühlt sich für dich „ok“ an.
- [ ] 20 Mal halten: Das Pop-up erscheint jedes Mal. Es gibt nie „vvv“ und nie Mehrfach-Einfügen. Popup-Latenz p90 unter 100 ms.
- [ ] Die Tasten 1–8 fügen den richtigen Dummy-Eintrag ein. Danach kannst du sofort weitertippen, ohne zu klicken.
- [ ] ⇧1 fügt unformatiert ein, 1 formatiert (TextEdit im Rich-Text-Modus).
- [ ] Esc schließt das Pop-up, nichts wird eingefügt, der Cursor bleibt, wo er war.
- [ ] ⌘⇧V, ⌥⌘V (Finder: Verschieben), ⌘C und ⌘X verhalten sich unverändert.
- [ ] Mit den Layouts Deutsch, US, Dvorak und „Dvorak – QWERTY ⌘“ funktionieren Tippen und Halten.
- [ ] In einem Passwortfeld funktioniert ⌘V normal; das Labor zeigt „Sichere Eingabe aktiv“.
- [ ] Bedienungshilfen bei laufender App aus: Die Tastatur funktioniert normal weiter. Wieder an: Der Tap ist ohne Neustart aktiv, oder es erscheint ein klarer Hinweis.
- [ ] Nach Ruhezustand und Benutzerwechsel ist der Tap aktiv.
- [ ] Runde 1 der Kompatibilitätsmatrix (Gruppe A) ist ausgefüllt.

---

### M2: Spike B – Zwischenablage, Datenschutz-Abfragen, Universal Clipboard

**Ziel:** Das Mitlesen der Zwischenablage ist auf deinem macOS zuverlässig, ohne Systemdialoge und datenschutzkonform. M1 und M2 können in einem gemeinsamen Build kommen, mit getrennten Checklisten.

**Aufgaben**
- **PR 2.1 (überwiegend CI):**
  - Markierungen: `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` und `source`, `com.apple.is-remote-clipboard`
  - Leser für die Zwischenablage: zuerst nur die Typen, dann Daten mit Größenbudget und Timeout
  - Schreiber: normal oder „nur dieser Mac“ (`.currentHostOnly`) mit Concealed-Markierung
  - Prüfung der Pasteboard-Freigabe (`accessBehavior`, detect-APIs)
  - Tests mit privaten Pasteboards
- **PR 2.2:**
  - Überwachung alle 0,4 s, Lesen im Hintergrund
  - Labor-Ansicht mit jeder Änderung: Typen, Quell-App, Größe, Lesedauer
  - Testknöpfe „normal schreiben“ und „nur lokal schreiben“
  - drei Lese-Modi für iPhone-Kopien: nur Typen / sofort lesen / erst bei Bedarf

**Fertig wenn**
- [ ] Jede Kopie erscheint im Labor mit Typen, Quell-App, Größe und Lesedauer.
- [ ] Kopien aus 1Password, Bitwarden und der Passwörter-App erscheinen als „übersprungen“, ohne dass Daten gelesen wurden. Das Ergebnis ist pro App dokumentiert.
- [ ] Eine iPhone-Kopie wird allein an den Typen als „vom iPhone“ erkannt. Für jeden Lese-Modus ist notiert, ob „Einfügen vom iPhone…“ erscheint.
- [ ] Ein „normal“ geschriebener Eintrag lässt sich auf dem iPhone einfügen, ein „nur lokal“ geschriebener nicht.
- [ ] Der `accessBehavior`-Wert ist dokumentiert. Mit der Einstellung „Fragen“ ist geprüft, ob das Mitlesen Dialoge auslöst. Der Weg zu „Immer erlauben“ ist notiert.
- [ ] Nach einem Arbeitstag mit laufendem Labor liegt die CPU bei etwa 0 % und die Energieauswirkung ist „niedrig“.
- [ ] Ein 5K-Screenshot und 50 MB Text in der Zwischenablage frieren die Oberfläche nicht ein.

#### Gate G1: Go/No-Go (nach M1 und M2)

**Weiter, wenn:**
- alle Punkte von M1 und M2 erfüllt sind,
- das Einfügen aus dem Pop-up in mindestens 90 % der Gruppe-A-Apps klappt,
- die Pasteboard-Freigabe ohne Dialogflut lösbar ist.

**Festzulegen:** D2, D3, D4, D13, die Wartezeit vor dem Einfügen und die ersten App-Ausnahmen.

**Plan B bei No-Go:** Die Halte-Geste wird optional und ist standardmäßig aus. Das Pop-up öffnet sich per Hotkey, ⌘V bleibt unangetastet. Der Rest des Plans bleibt gültig.

---

### M3: Kern und Speicher (parallel zu M1/M2, über CI geprüft)

**Ziel:** fertige, getestete Datenschicht inklusive Verschlüsselung.

**Aufgaben**
- **PR 3.1:** Datenmodell, Inhaltserkennung (Grundtypen), Fingerprint, Verlaufsregeln (Limit, Favoriten ausgenommen, Ablauf) und Suche (Groß-/Kleinschreibung und Akzente egal, Ranking nach Aktualität).
- **PR 3.2:** Datenbank (WAL, Migration v1) und Repository mit diesen Operationen:
  - Einfügen, nach oben rücken, Inhalt ersetzen
  - Anpinnen, Lösen, Sortieren
  - Löschen, alles löschen
  - Abfragen
  - Abgelaufenes entfernen, Limit durchsetzen
- **PR 3.3:** Verschlüsselung, Keychain-Schlüssel, Blob-Ablage, Aufräumen verwaister Dateien, Ablauf bei Schlüsselverlust.

**Fertig wenn**
- [ ] Alle Storage-Tests in der CI sind grün, inklusive Performance-Test mit 10.000 Einträgen: die letzten 8 abfragen unter 5 ms, Einfügen unter 10 ms.
- [ ] Lokal ist `swift test` grün. Der Keychain-Schlüssel wird nach einem Rebuild ohne Passwortdialog gelesen.

---

### M4: Alpha – echter Verlauf und Pop-up (Beginn der Alltagsnutzung)

**Ziel:** täglich benutzbar. Text, formatierter Text, Bilder und Dateien werden erfasst und eingefügt; der Basis-Datenschutz ist aktiv.

**Aufgaben**
- **PR 4.1:** Erfassen, Datenschutz-Filter (Markierungen, Standard-Ignore-Liste, eigene Schreibvorgänge), Verlauf.
  - Bilder als PNG speichern.
  - Dateien nur als Verweis speichern.
  - Größenlimits vorläufig fest (D6).
- **PR 4.2:** Einfügen und Pop-up mit echten Daten (Nummer, Typ-Symbol, erste Zeile), alle Tasten aus 1.8 außer ⌘P. Die obersten 8 Vorschauen liegen ständig entschlüsselt im Speicher.
- **PR 4.3:**
  - Menü „Verlauf öffnen“, „Verlauf löschen…“, „Diagnose“, „Beenden“
  - Fallback-Hotkey (D5)
  - ohne Freigabe: Eintrag nur in die Zwischenablage legen und „Jetzt ⌘V drücken“ anzeigen
  - Pop-up oben mittig bzw. an der Notch, mit einfacher Animation
- **PR 4.4:** Korrekturen aus der Alltagsnutzung.

**Fertig wenn**
- [ ] Du kopierst 10 Texte aus verschiedenen Apps. ⌘V halten zeigt die letzten 8 in der richtigen Reihenfolge.
- [ ] Taste 3 fügt Eintrag 3 ein; er steht danach oben, und ein kurzes ⌘V fügt ihn erneut ein.
- [ ] ⇧2 fügt einen formatierten Eintrag unformatiert ein.
- [ ] Denselben Text zweimal kopieren ergibt einen Eintrag, der nach oben rückt.
- [ ] Tippen von „rech“ filtert auf „Rechnung…“; ↩ fügt den ersten Treffer ein.
- [ ] Ein Screenshot und Finder-Dateien lassen sich über das Pop-up wieder einfügen.
- [ ] Ein Passwort aus dem Passwortmanager taucht nicht im Verlauf auf.
- [ ] Nach Beenden und Neustart ist der Verlauf noch da.
- [ ] `grep -ra "<kopiertes Wort>" ~/Library/Application\ Support/<bundle-id>/` findet nichts, die Daten sind also verschlüsselt.
- [ ] Mit 100 Einträgen liegt die CPU im Leerlauf bei etwa 0 % und der Speicher unter 50 MB.

#### Gate G2 (nach einer Woche Alltagsnutzung)

- Keine Abstürze, keine verschluckten Einfügungen.
- Fühlt sich das Halten gut an? Schwelle und Wartezeit bei Bedarf anpassen.
- Prioritäten für M5 bis M7 prüfen.

---

### M5: Datenschutz komplett (Alleinstellungsmerkmal)

**Aufgaben**
- **Erkennung sensibler Inhalte:**
  - **IBAN:** Ländertabelle und Prüfziffer (Modulo 97)
  - **Kartennummern:** 13–19 Ziffern, Luhn-Prüfung, bekannte Nummernkreise
  - **API-Keys und Tokens:** AWS, GitHub, Slack, Stripe, OpenAI, Anthropic, Google, JWT, private PEM-Schlüssel
  - **Einmalcodes:** optional; ob sie standardmäßig erkannt werden, wird in M5 entschieden
- **Darstellung sensibler Einträge:**
  - maskiert (z. B. „DE89 •••• … 3000“)
  - nicht durchsuchbar
  - Anzeige nur auf ausdrückliche Aktion
  - pro Eintrag „Nicht sensibel“ wählbar
- **Automatisches Löschen:**
  - sensible Einträge nach etwa 60 s
  - übrige Einträge nach der eingestellten Aufbewahrungsdauer und beim Überschreiten des Größenlimits
  - optional auch die Zwischenablage leeren (standardmäßig aus)
- **Einfügen sensibler Einträge:** „nur auf diesem Mac“ plus Concealed-Markierung, damit sie weder aufs iPhone gehen noch von anderen Clipboard-Managern gespeichert werden.
- **Ignore-Liste:**
  - Standardliste: Passwortmanager, Schlüsselbund, Passwörter-App, Banking-Apps
  - eigene Apps hinzufügen, Standard wiederherstellen
- **Aufzeichnung pausieren** (15 Min. / 1 Std. / bis zur Reaktivierung), mit eigenem Menüleisten-Symbol.
- **„Verlauf löschen“** mit Bestätigung.
- **Debug-Funktion „Zeit +N Tage“** zum Testen der Aufbewahrung.
- **Testkorpus** mit mindestens 50 Positiv- und Negativbeispielen, auch für Fehlalarme wie Telefon- oder Bestellnummern.

**Fertig wenn**
- [ ] `DE89 3704 0044 0532 0130 00` erscheint maskiert und ist nach etwa 60 s verschwunden. `DE88…` (falsche Prüfziffer) wird ein normaler Eintrag.
- [ ] `4242 4242 4242 4242` ist sensibel, `4242 4242 4242 4241` nicht.
- [ ] `AKIAIOSFODNN7EXAMPLE` und ein Beispiel-JWT werden als sensibel erkannt.
- [ ] Ein sensibler Eintrag wird am Mac korrekt eingefügt, auf dem iPhone kommt er **nicht** an.
- [ ] Steht TextEdit auf der Ignore-Liste, wird nichts erfasst; nach dem Entfernen wieder.
- [ ] Während „Pausieren 15 Min.“ zeigt das Icon die Pause, und es wird nichts erfasst.
- [ ] Aufbewahrung 1 Tag plus „Zeit +2 Tage“: Alte Einträge sind weg.
- [ ] Nach „Verlauf löschen“ sind auch die Blob-Dateien weg.
- [ ] Der Korpus in der CI hat 0 Fehlklassifikationen.

---

### M6: Vorschauen und Favoriten

**Aufgaben**
- **Erkennung:**
  - Links (Domain und Pfad)
  - Farben (`#RGB`, `#RRGGBB(AA)`, `rgb()`, `hsl()`, Farbobjekte)
  - Dateien (Anzahl, Namen, Icons)
  - formatierter Text (Hinweis „formatiert“)
- **Miniaturen** für Bilder, maximal 256 px, verschlüsselt zwischengespeichert.
- **Jede Zeile zeigt** das Icon der Quell-App, die relative Zeit („vor 2 Min.“) und ein iPhone-Symbol bei iPhone-Einträgen.
- **Website-Icons (Favicons)** nur gemäß D7, weil sie eine Netzwerkanfrage brauchen.
- **Favoriten:**
  - ⌘P im Pop-up, ⇥ wechselt zur Favoritenansicht
  - in den Einstellungen benennen (z. B. „E-Mail privat“), sortieren, löschen
  - ausgenommen von Aufbewahrungsdauer, Größenlimit und „Verlauf löschen“

**Fertig wenn**
- [ ] Bilder zeigen eine Miniatur, Links Domain und Pfad, `#FF8800` und `rgb(255,136,0)` ein oranges Farbfeld, Dateien Icons und Namen, formatierter Text den Hinweis „formatiert“.
- [ ] Jede Zeile zeigt Quell-App-Icon und relative Zeit; iPhone-Einträge sind gekennzeichnet.
- [ ] ⌘P macht einen Eintrag zum Favoriten, ⇥ zeigt die Favoriten, und 1 fügt den ersten ein.
- [ ] Favoriten lassen sich benennen und sortieren. Sie überstehen „Verlauf löschen“ und die Aufbewahrungsfrist.
- [ ] Die Popup-Latenz bleibt mit 8 Bild-Miniaturen unter 100 ms (p90).

---

### M7: Notch-Erlebnis, Onboarding, Einstellungen, Start bei Anmeldung

**Aufgaben**
- **Notch-Geometrie** (rein, getestet): Rechteck der Notch, sonst oben mittig. Es zählt der Bildschirm mit dem aktiven Fenster, ersatzweise der mit dem Mauszeiger.
- **Animation:** Das Pop-up wächst als schwarze Form aus der Notch. Im Labor zeigt ein Overlay die berechnete Notch.
- **„Kopiert ✓“** als kurze Rückmeldung in der Notch, abschaltbar.
- **Onboarding:**
  1. Willkommen
  2. Datenschutzversprechen
  3. Bedienungshilfen (mit Direktlink und automatischer Erkennung)
  4. Zugriff auf die Zwischenablage („Immer erlauben“)
  5. Übungsfeld „Halte ⌘V“
  6. Start bei Anmeldung
- **Einstellungen:**
  - Allgemein: Schwelle, Hotkey, Animation, Start bei Anmeldung
  - Verlauf: Größe, Aufbewahrung, Umgang mit iPhone-Kopien
  - Datenschutz
  - Favoriten
  - Über
- **Start bei Anmeldung** über `SMAppService`, inklusive Fall „Freigabe nötig“.
- **Wird die Bedienungshilfen-Freigabe zur Laufzeit entzogen:** Warn-Icon in der Menüleiste und Menüeintrag „Berechtigung erneut erteilen“.
- **Abschluss:** String Catalog mit allen Texten (und ggf. Englisch, D9), VoiceOver-Beschriftungen, App- und Menüleisten-Icon (nach D8).

**Fertig wenn**
- [ ] Auf einem Mac mit Notch wächst das Pop-up sichtbar aus der Notch.
- [ ] Mit externem Monitor bzw. ohne Notch läuft dieselbe Animation oben mittig auf dem Bildschirm mit dem aktiven Fenster.
- [ ] Im Vollbild, mit Stage Manager und mit ausgeblendeter Menüleiste klappen Pop-up und Einfügen.
- [ ] „Kopiert ✓“ erscheint beim Kopieren; abgeschaltet erscheint nichts.
- [ ] Nach einem frischen Start (`scripts/reset-dev-state.sh`) führt das Onboarding in unter 2 Minuten ohne Hilfe durch alle Schritte.
- [ ] Jede Einstellung wirkt sofort, ohne Neustart.
- [ ] „Start bei Anmeldung“ an: CopyPal läuft nach einem Neustart des Macs. Aus: CopyPal läuft nicht.
- [ ] Bei entzogener Freigabe erscheint das Warn-Icon, und der Menüeintrag führt zur Freigabe.

---

### M8: Härtung, Performance, Kompatibilität

**Aufgaben**
- **Messen:** Instruments (CPU, Speicher, Energie) und Messpunkte für „Halten bis sichtbar“ und „Kopieren bis gespeichert“.
- **Mitlesen pausieren** bei Bildschirmsperre und Ruhezustand.
- **Robustheit** bei Ruhezustand über Nacht, Monitorwechsel und Benutzerwechsel.
- **Logs** enthalten nie Inhalte der Zwischenablage.
- **Vollständige Kompatibilitätsmatrix** und Standardliste „Halten aus“ (VMs, Remote-Desktop, Spiele).
- **Smoke-Test auf macOS 14** in einer VM (UTM oder VirtualBuddy).
- **In der Diagnose:** „Letzten Absturzbericht anhängen“.

**Fertig wenn**
- [ ] Die CPU liegt im Leerlauf unter 0,1 % (10 Minuten in der Aktivitätsanzeige gemessen).
- [ ] Der Speicher bleibt bei 500 Einträgen (davon 50 Bilder) unter 50 MB.
- [ ] Die Popup-Latenz liegt p90 unter 100 ms. *(CI-VM: p90 55 ms auf macOS 15, 62 ms auf macOS 14)*
- [ ] Ein 20-MB-Bild zu kopieren erzeugt kein Ruckeln. *(CI-VM: längste Blockade 39 bzw. 45 ms)*
- [ ] `for i in {1..100}; do echo $i | pbcopy; sleep 0.1; done`: kein Absturz, keine Duplikate, der letzte Eintrag ist korrekt. *(im CI-Selbsttest nachgestellt: bestanden)*
- [ ] Die Matrix ist vollständig; jede rote Zelle hat eine Umgehung oder eine App-Ausnahme.
- [x] Der Smoke-Test auf macOS 14 ist bestanden. *(CI, macOS 14.8.9, alle 28 Selbsttest-Prüfungen, 12.10.2026)*
- [ ] 2 Wochen ohne Absturz, keine offenen kritischen Fehler.

#### Gate G3: Bereit für die Beta

D8, D10, D11 und D12 sind entschieden, und es gibt keine kritischen Fehler.

---

### M9: Beta-Vertrieb

**Aufgaben**
- **Apple Developer Program abschließen** (99 $/Jahr, D10) und die endgültige Bundle-ID festlegen (D8).
- **Repo-Umzug** gemäß D1.
- **`scripts/release.sh`** läuft lokal auf deinem Mac, damit Zertifikate nicht in die CI müssen:
  1. Archiv bauen
  2. mit „Developer ID“ exportieren
  3. notarisieren und stapeln
  4. DMG erstellen
  5. DMG signieren und notarisieren
  6. Update-Feed (Appcast) erzeugen
- **Sparkle 2:** „Nach Updates suchen…“, Beta-Kanal, keine Systemprofil-Übertragung.
- **Signaturschlüssel für Updates erzeugen** und an **zwei** Orten sichern.
- **Appcast hosten**, z. B. über GitHub Pages.
- **Anleitung für Tester:** Installation, Freigaben, Feedback-Weg.

**Fertig wenn**
- [ ] `spctl -a -vvv -t install CopyPal.dmg` meldet „Notarized Developer ID“.
- [ ] Das DMG öffnet sich auf einem anderen Mac oder Benutzerkonto ohne Gatekeeper-Blockade.
- [ ] Ein Update von 0.9.0 auf 0.9.1 klappt, und die Bedienungshilfen-Freigabe bleibt erhalten.
- [ ] Die Wiederherstellung des Update-Schlüssels aus dem Backup ist ausprobiert.
- [ ] 5–15 Tester haben installiert und das Onboarding ohne Hilfe geschafft.

---

### M10: Release 1.0

**Aufgaben**
- **Preismodell umsetzen (D11).** Falls kostenpflichtig: über einen Merchant of Record (wegen der EU-Umsatzsteuer) mit Lizenzschlüssel, der offline geprüft wird.
- **Landingpage** mit Download, Funktionen, Datenschutzversprechen und FAQ zu den Berechtigungen.
- **Impressum und Datenschutzerklärung.**
- **Letzte Kompatibilitätsrunde** auf aktuellem macOS und auf macOS 14.
- **Abgrenzung** zum eingebauten Spotlight-Verlauf von macOS.

**Fertig wenn**
- [ ] `Docs/Release-Checkliste.md` ist vollständig abgehakt.
- [ ] Die Website ist live, mit notarisiertem DMG und Update-Feed.
- [ ] Falls kostenpflichtig: Kauf, Aktivierung und Rückerstattung sind einmal komplett durchgespielt.
- [ ] Alle offenen Entscheidungen sind abgeschlossen.

---

## 4. Teststrategie

### 4.1 Automatisiert (Swift Testing, bei jedem PR in der CI)

| Bereich | Was wird getestet |
|---|---|
| Zustandsautomat der Halte-Geste | Tabelle aus 1.7 vollständig, mit gesteuerter Zeit und Schwellengrenzen |
| Erkennung sensibler Inhalte | Korpus mit Positiv- und Negativbeispielen, IBAN-Prüfziffer je Land, Luhn, Schlüsselmuster, Maskierung |
| Inhaltserkennung | Varianten und Randfälle bei Links, Farben und Dateien |
| Verlauf und Duplikate | gleicher Inhalt, erneutes Kopieren, eigene Schreibvorgänge, iPhone-Platzhalter |
| Aufbewahrung | Limits, Favoriten ausgenommen, Ablaufzeiten |
| Suche, Notch-Geometrie | Ranking, Umlaute; Notch, ohne Notch, mehrere Bildschirme |
| Speicher | Migrationen, Ver- und Entschlüsselung, Manipulationserkennung, Schlüsselverlust, verwaiste Dateien, 10.000-Einträge-Performance |
| Lesen und Schreiben der Zwischenablage | private Pasteboards: Markierungen, mehrere Items, Datei-URLs, RTF plus Text |

- **Bewusst nicht automatisiert:** Event-Tap, Freigaben, Fokus, Universal Clipboard und Notch. Diese Punkte werden von Hand geprüft.
- **Hinweis zu Test-Tokens:** GitHub blockiert Pushes mit echt aussehenden Tokens. In Tests daher nur dokumentierte Beispielschlüssel verwenden oder die Strings zur Laufzeit zusammensetzen.

### 4.2 Manuell

- **Pro Meilenstein ein Testplan** `Docs/Testplaene/M<N>.md`: die „Fertig wenn“-Punkte mit Schritten und erwartetem Ergebnis.
- **Regressions-Kurztest (10 Min.) vor jedem Merge ab M4:** Tippen, Halten, 1–8, ⇧, Suche, Passwortmanager, Neustart.

### 4.3 Kompatibilitätsmatrix (`Docs/Kompatibilitaet.md`)

**Spalten:** Tippen ⌘V · Halten → Pop-up · Text · formatierter Text · ⇧ als reiner Text · Bild · Fokus bleibt · Bemerkung.

| Gruppe | Apps |
|---|---|
| **A (muss vor der Beta passen)** | TextEdit, Notizen, Mail, Safari (Adressleiste, Textfeld, Google Docs), Chrome, Terminal, VS Code, Slack, Word, Finder (Dateien, Umbenennen), Nachrichten |
| **B (sollte passen)** | Firefox, Arc/Edge, iTerm2, Xcode, Pages/Numbers/Keynote, Excel, Outlook, PowerPoint, Teams, Notion, Obsidian, Figma, JetBrains-IDEs, Spotlight |
| **C (dokumentieren, ggf. App-Ausnahme)** | Passwortfelder, Parallels/UTM/VMware, Remote-Desktop, Spiele, japanische/chinesische Eingabe, Diktat |
| **Tool-Konflikte** | Karabiner-Elements, BetterTouchTool, Keyboard Maestro, TextExpander, Raycast/Alfred |

**Runden:** M1 (Gruppe A, nur Tippen, Halten und Fokus) · M4 (Gruppe A vollständig) · M8 (alle) · vor jedem Release (Gruppe A).

### 4.4 Performance-Ziele

- CPU im Leerlauf etwa 0 %
- Speicher unter 50 MB
- Pop-up unter 100 ms (p90) nach Erreichen der Schwelle

---

## 5. Risiken und Gegenmaßnahmen

| # | Risiko | Gegenmaßnahme | Geprüft in |
|---|---|---|---|
| R1 | Kurzes ⌘V fügt erst beim Loslassen ein und wirkt träge | Tipp-Dauer messen; Schwelle einstellbar; „Halten aus“ pro App; Plan B Hotkey | M1, G1, G2 |
| R2 | Fokus kehrt nach dem Pop-up nicht zurück (Electron, Office, Web-Editoren) | Wartezeit; Prüfung der vorderen App; sonst nur in die Zwischenablage mit Hinweis; Tasten-Weiterleitung (D4) | M1, M8 |
| R3 | Pasteboard-Datenschutz fragt oder blockiert das Mitlesen (jetzt oder in künftigen macOS-Versionen) | Prüfung schon in M0; Onboarding „Immer erlauben“; bei „Fragen“ sichtbar pausieren statt Dialogflut; jede macOS-Beta testen | M0, M2, laufend |
| R4 | Bedienungshilfen-Freigabe geht bei Rebuilds verloren | Personal-Team-Signierung; eigene Dev-Bundle-ID; Anleitung in `Troubleshooting.md` | M0 |
| R5 | iPhone-Kopien lösen „Einfügen vom iPhone…“ aus | zuerst nur Typen lesen; Einstellung D3 | M2 |
| R6 | Event-Tap wird deaktiviert oder blockiert die Eingabe | eigener Thread; schneller Callback; Wieder-Einschalten; Wächter | M1, M8 |
| R7 | Secure Input verhindert das Halten | normales ⌘V funktioniert weiter; Diagnose zeigt die verursachende App | M1 |
| R8 | Tastaturlayouts und Eingabemethoden | Layout-Erkennung mit ⌘; Kompatibilitätsmatrix | M1 |
| R9 | Konflikte mit Tastatur-Tools, VMs, Remote-Desktop | fremde synthetische Events durchlassen; „Halten aus“ pro App | M1, M8 |
| R10 | Keychain-Schlüssel nach Signatur- oder Team-Wechsel unlesbar | Ablauf bei Schlüsselverlust; nach der ersten Beta kein Team-Wechsel mehr | M3, M9 |
| R11 | Fehlalarme oder übersehene sensible Inhalte | Prüfsummen; zurückhaltende Muster; Korpus-Tests; „Nicht sensibel“ pro Eintrag | M5 |
| R12 | Speicherbedarf durch große Inhalte | Größenlimits; Blobs auf der Platte; Miniaturen; nur die neuesten Einträge im RAM | M4, M8 |
| R13 | Claude kann nicht selbst kompilieren | CI bei jedem PR; kleine PRs; Logik im Package | M0 |
| R14 | CI-Kosten (macOS-Minuten) | Pfadfilter, Abbruch alter Läufe, Cache; öffentliches Repo oder eigener Runner | M0 |
| R15 | Unterschiedliche Xcode-Versionen bei dir und in der CI | CI baut mit Xcode 26.0 wie dein Mac (Diagnose „Gebaut mit“); bei Xcode-Updates beide anheben | M0 |
| R16 | Nur ein Test-Mac, Mindestversion ist macOS 14 | VM mit macOS 14; Beta-Tester mit älteren Macs bzw. Macs ohne Notch | M8, M9 |
| R17 | Notch-Geometrie, mehrere Bildschirme, Vollbild | getestete Geometrie; Labor-Overlay; Rückfall oben mittig; Panel wandert beim Öffnen auf den aktiven Space (`moveToActiveSpace`), ein unsichtbares Pop-up wird abgebrochen statt die Geste zu blockieren | M7 |
| R18 | Name „CopyPal“ markenrechtlich oder als Domain belegt | früh prüfen: DPMA, EUIPO, USPTO, App Store, Domains | D8 |
| R19 | Privater Update-Schlüssel verloren, dann keine Updates mehr möglich | Backup an zwei Orten, Wiederherstellung ausprobiert | M9 |
| R20 | Apple schränkt synthetische Eingaben weiter ein | Rückfall „nur in die Zwischenablage legen“; Betas beobachten | laufend |
| R21 | Kopien, die schneller als 0,4 s aufeinander folgen, werden verpasst | akzeptiert und dokumentiert | M2 |
| R22 | Konkurrenz durch den Spotlight-Verlauf ab macOS 26 | Abgrenzung über ⌘V-Halten, Datenschutz, Verschlüsselung, Favoriten | M10 |

---

## 6. Offene Entscheidungen

| # | Entscheidung | Empfehlung | Spätestens |
|---|---|---|---|
| D1 | Repo: Sichtbarkeit und Ort | jetzt `Test-1/CopyPal` (privat: macOS-CI-Minuten zählen zehnfach), vor der Beta in ein eigenes Repo | Sichtbarkeit: M0 · Umzug: M9 |
| D2 | Standard-Halteschwelle | Start mit 0,3 s, endgültiger Wert nach Messung | G1 |
| D3 | Umgang mit iPhone-Kopien | nach Messung in M2; als Einstellung | G1 |
| D4 | Tasteneingabe ins Pop-up | Key-Panel; Tasten-Weiterleitung nur, wenn es Fehlschläge gibt | G1 |
| D5 | Fallback-Hotkey | ⌃⌥V, frei belegbar | M4 |
| D6 | Standardwerte | 500 Einträge · 30 Tage · sensibel 60 s · Text 2 MB · Bild 25 MB · insgesamt 1 GB | M5 |
| D7 | Favicons laden (Netzwerk) | nur auf Wunsch, passend zum Versprechen „alles lokal“ | vor M6 |
| D8 | Name, Marke, Bundle-ID, Domain | jetzt prüfen (etwa 1 Std.) | vor M7 |
| D9 | Sprachen in 1.0 | Deutsch und Englisch | Start M7 |
| D10 | Apple Developer Program | als Einzelperson (sofort aktiv); als Organisation mehrere Wochen Vorlauf wegen D-U-N-S-Nummer | Ende M8 |
| D11 | Preismodell | offen; falls kostenpflichtig, über einen Merchant of Record | Start M9 |
| D12 | Beta-Programm | 5–15 Tester, Sparkle-Beta-Kanal | Start M9 |
| D13 | Mindestversion macOS 14 bestätigen | 14 | G1 |

---

## 7. Backlog nach 1.0

- **v1.x:**
  - „Sammeln“-Modus: jedes ⌘V fügt den nächsten Eintrag aus einer Warteschlange ein
  - Texterkennung in Bildern (Vision) für die Suche
  - Tracking-Parameter aus Links entfernen (utm_*, fbclid, gclid …)
  - Durchblättern durch wiederholtes V (wie ⌘-Tab) als Profi-Option
  - Favoriten exportieren und importieren
  - Pop-up direkt am Textcursor
- **v2:**
  - iCloud-Sync über CKSyncEngine (das Schema ist vorbereitet), mit Ende-zu-Ende-Verschlüsselung über einen eigenen Schlüssel im iCloud-Schlüsselbund
  - `local_only`-Einträge werden nie synchronisiert
  - iPhone-App mit Verlauf und Tastatur

---

## 8. Troubleshooting (wird nach `Docs/Troubleshooting.md` übernommen)

- **Freigabe hängt:**
  1. `tccutil reset Accessibility <bundle-id>`
  2. in Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen den alten Eintrag entfernen
  3. App starten und neu freigeben
- **Signatur prüfen:** `codesign -dv --verbose=4 <Pfad>/CopyPal.app 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier'`
- **Secure Input finden:** `ioreg -l -w 0 | grep -i SecureInput`
- **Logs live ansehen:** `log stream --predicate 'subsystem == "<bundle-id>"' --level debug`
- **Bundle-ID einer App:** `osascript -e 'id of app "1Password"'`
- **Entwicklungsstand zurücksetzen** (`scripts/reset-dev-state.sh`): Freigaben, Einstellungen, Datenordner und den Keychain-Eintrag löschen.
- **Notarisierung prüfen:** `spctl -a -vvv -t install CopyPal.dmg` und `xcrun stapler validate CopyPal.dmg`.
