# CopyPal Beta – Anleitung für Testerinnen und Tester

Danke fürs Testen! CopyPal ist ein Clipboard-Manager für den Mac:

- **⌘V kurz drücken** fügt wie gewohnt ein.
- **⌘V halten** öffnet deine letzten Kopien an der Notch.

## Installation (2 Minuten)

1. `CopyPal-<version>.dmg` öffnen und CopyPal in **Programme** ziehen.
2. CopyPal starten. Das Onboarding führt durch alles:
   - **Bedienungshilfen**: nötig, damit CopyPal kurzes und langes ⌘V unterscheiden kann. CopyPal liest dabei keine Tastatureingaben mit.
   - **Zugriff auf die Zwischenablage** (ab macOS 15.4): „Immer erlauben“ wählen.
   - **Übungsfeld**: einmal ⌘V halten und 2 drücken.
   - **Bei der Anmeldung starten**: empfohlen.
3. Updates kommen automatisch, wenn du es beim zweiten Start erlaubst. Sonst über Menüleiste → „Nach Updates suchen …“.

## Was du ausprobieren kannst

- Kopiere wie immer. ⌘V halten zeigt die letzten 8 Einträge. `1`–`8` fügt ein, `⇧` ohne Formatierung.
- Einfach lostippen: Das Pop-up sucht.
- `⇥` zeigt die Favoriten, `⌘P` pinnt den ausgewählten Eintrag an.
- Menüleiste → Verlauf öffnen: alle Einträge, Favoriten benennen und sortieren.
- Passwörter aus deinem Passwortmanager landen nie im Verlauf. IBAN, Kartennummern und Schlüssel erscheinen verdeckt und verschwinden nach einer Minute.
- `⌘⇧A` macht ein Bildschirmfoto: Maus über ein Fenster oder einen Bereich, Klick kopiert das Bild, `⇧`-Klick nur den Text, Ziehen wählt frei – danach stehen alle Möglichkeiten als Knöpfe unter der Auswahl. `↓` scrollt weiter und setzt alles zu einem langen Bild zusammen. Beim ersten Mal fragt CopyPal nach der Freigabe „Bildschirmaufnahme“; ab macOS 15 fragt macOS etwa einmal im Monat erneut nach – das ist normal.

## Datenschutz

Alles bleibt verschlüsselt auf deinem Mac. Es gibt keine Konten, keine Cloud und keine Nutzungsstatistik. Ins Netz geht CopyPal nur für Updates, und nur mit deiner Zustimmung.

## Feedback

- **Fehler oder Ideen**: als GitHub-Issue oder per E-Mail an die Adresse aus der Einladung.
- Bitte immer anhängen:
  - Menüleiste → **Diagnose …** → „Bericht kopieren“. Der Bericht enthält keine Inhalte deiner Zwischenablage und keinen Namen.
  - Nach einem Absturz: Diagnose → „Absturzbericht kopieren“.
- Was dabei hilft: welche App, was du getan hast, was passiert ist und was du erwartet hast.

## Wenn etwas hakt

- **⌘V halten reagiert nicht**: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen: CopyPal aus- und wieder einschalten.
- **In einer App soll ⌘V unverändert bleiben** (z. B. eine VM): Einstellungen → Allgemein → „Apps ohne ⌘V halten“.
- **Pause**: Menüleiste → Aufzeichnung pausieren.
- **Deinstallieren**: CopyPal beenden und löschen. Der Verlauf liegt unter `~/Library/Application Support/<bundle-id>`, der Schlüssel in der Schlüsselbundverwaltung („CopyPal“).
