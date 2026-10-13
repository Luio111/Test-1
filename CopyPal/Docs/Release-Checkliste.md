# Release-Checkliste 1.0 (M10)

Vor jedem Release abhaken; für 1.0 vollständig.

## Entscheidungen (ROADMAP §6)

- [ ] D1 Repository: öffentliches Website-/Release-Repository angelegt, App-Code verschoben oder privat belassen
- [ ] D2 Halteschwelle festgelegt (nach G1/G2): ___ s
- [ ] D3 iPhone-Kopien: Standard „Erst bei Auswahl laden“ bestätigt
- [ ] D4 Tasteneingabe ins Pop-up: Key-Panel bestätigt (oder Tasten-Weiterleitung nötig)
- [ ] D5 Fallback-Hotkey ⌃⌥V bestätigt
- [ ] D6 Standardwerte bestätigt: 500 Einträge · 30 Tage · sensibel 60 s · Text 2 MB · Bild 25 MB · insgesamt 1 GB
- [ ] D7 Website-Symbole: standardmäßig aus
- [ ] D8 Name, Marke (DPMA, EUIPO, USPTO), Domain, Bundle-ID geprüft
- [ ] D9 Sprachen: Deutsch und Englisch vollständig
- [ ] D10 Apple Developer Program aktiv
- [ ] D11 Preismodell entschieden; falls kostenpflichtig: Merchant of Record, Lizenzschlüssel (offline geprüft, `LicenseProvider`)
- [ ] D12 Beta mit 5–15 Personen abgeschlossen
- [ ] D13 Mindestversion macOS 14 bestätigt

## Qualität

- [ ] CI grün auf dem Release-Commit (Package-Tests, App-Build, Selbsttest)
- [ ] Testpläne M1–M8 auf aktuellem macOS abgehakt
- [ ] Smoke-Test auf macOS 14 (VM, oder „CopyPal CI“ von Hand mit „Zusätzlich Selbsttest auf macOS 14“)
- [ ] Kompatibilitätsmatrix Gruppe A aktuell (`Docs/Kompatibilitaet.md`)
- [ ] Keine offenen kritischen Fehler, zwei Wochen ohne Absturz
- [ ] Performance: Leerlauf-CPU < 0,1 %, Speicher < 50 MB, Pop-up p90 < 100 ms

## Build und Vertrieb

- [ ] `MARKETING_VERSION` = 1.0.0, Changelog geschrieben
- [ ] `./scripts/release.sh 1.0.0` ohne Fehler
- [ ] `spctl -a -vvv -t install CopyPal-1.0.0.dmg` → „Notarized Developer ID“
- [ ] DMG auf einem anderen Mac ohne Gatekeeper-Blockade geöffnet
- [ ] Update von der letzten Beta auf 1.0.0 geklappt, Bedienungshilfen-Freigabe blieb erhalten
- [ ] Appcast auf GitHub Pages veröffentlicht, Feed-URL erreichbar
- [ ] Update-Schlüssel an zwei Orten gesichert, Wiederherstellung einmal ausprobiert

## Website und Rechtliches

- [ ] Landingpage (`CopyPal/Website/`) mit echtem Download-Link, Funktionen, Datenschutzversprechen, FAQ
- [ ] Impressum mit vollständigen Angaben (§ 5 DDG)
- [ ] Datenschutzerklärung geprüft (Hosting, Update-Prüfung, Website-Symbole)
- [ ] Falls kostenpflichtig: Kauf, Aktivierung und Rückerstattung einmal komplett durchgespielt
- [ ] Abgrenzung zum Spotlight-Verlauf in den FAQ
