# Kompatibilitätsmatrix

Pro App: ✓ klappt · ✗ klappt nicht · ~ mit Einschränkung (Bemerkung) · – nicht anwendbar.
Runden laut ROADMAP §4.3: M1 (Gruppe A: Tippen, Halten, Fokus) · M4 (Gruppe A vollständig) · M8 (alle) · vor jedem Release (Gruppe A).

**Spalten**
- **Tippen**: ⌘V kurz drücken fügt wie gewohnt ein.
- **Halten**: ⌘V halten öffnet das Pop-up.
- **Text**: einfacher Text über das Pop-up.
- **Format**: formatierter Text bleibt formatiert.
- **⇧**: ⇧+Zahl fügt reinen Text ein.
- **Bild**: Bild über das Pop-up.
- **Fokus**: Nach dem Einfügen kann man ohne Klick weitertippen.

## Gruppe A – muss vor der Beta passen

| App | Tippen | Halten | Text | Format | ⇧ | Bild | Fokus | Bemerkung |
|---|---|---|---|---|---|---|---|---|
| TextEdit (Rich Text) | | | | | | | | |
| Notizen | | | | | | | | |
| Mail (neue E-Mail) | | | | | | | | |
| Safari – Adressleiste | | | | – | | – | | |
| Safari – Textfeld | | | | | | | | |
| Safari – Google Docs | | | | | | | | |
| Chrome | | | | | | | | |
| Terminal | | | | – | | – | | |
| VS Code | | | | – | | – | | |
| Slack | | | | | | | | |
| Word | | | | | | | | |
| Finder – Dateien | | | – | – | – | – | | Dateien über das Pop-up einfügen |
| Finder – Umbenennen | | | | – | | – | | |
| Nachrichten | | | | | | | | |

## Gruppe B – sollte passen

| App | Tippen | Halten | Text | Format | ⇧ | Bild | Fokus | Bemerkung |
|---|---|---|---|---|---|---|---|---|
| Firefox | | | | | | | | |
| Arc / Edge | | | | | | | | |
| iTerm2 | | | | – | | – | | |
| Xcode | | | | – | | – | | |
| Pages / Numbers / Keynote | | | | | | | | |
| Excel / PowerPoint | | | | | | | | |
| Outlook | | | | | | | | |
| Teams | | | | | | | | |
| Notion | | | | | | | | |
| Obsidian | | | | | | | | |
| Figma | | | | | | | | |
| JetBrains-IDEs | | | | – | | – | | |
| Spotlight | | | | – | | – | | |

## Gruppe C – dokumentieren, ggf. App-Ausnahme

| Situation | Verhalten | Umgehung |
|---|---|---|
| Passwortfelder (Secure Input) | Tippen geht normal. Halten öffnet **kein** Pop-up, weil macOS keine Tasten an Event-Taps gibt. | Tastenkürzel ⌃⌥V öffnet das Pop-up; der Eintrag landet in der Zwischenablage. |
| Parallels / UTM / VMware / VirtualBox | Stehen in „Apps ohne ⌘V halten“: ⌘V geht unverändert an die VM. | Liste in Einstellungen → Allgemein |
| Remote-Desktop, Bildschirmfreigabe, TeamViewer, AnyDesk, Citrix | wie VMs | wie VMs |
| Spiele | | bei Bedarf in die Liste aufnehmen |
| Japanische/chinesische Eingabe | Suche im Pop-up nimmt nur direkt getippte Zeichen (keine Kandidatenauswahl). | Suchen mit lateinischen Buchstaben oder im Verlaufsfenster |
| Diktat | | |

## Bildschirmfoto (M11)

**Einrasten**: Klick auf Button, Bild, Absatz und Fenster liefert den passenden Ausschnitt. **Erweitern**: ↓ setzt die Seite ohne doppelte oder fehlende Zeilen zusammen. **Einfügen**: Das Ergebnis lässt sich dort einfügen.

| App | Einrasten | Erweitern | Einfügen | Bemerkung |
|---|---|---|---|---|
| Safari | | | | Einfügen nutzt TIFF |
| Chrome | | | | ⌘⇧A ist dort „Tabs durchsuchen“ – CopyPal hat Vorrang |
| Firefox | | | | |
| Arc | | | | |
| Notion | | | | fester Header: erscheint einmal |
| Slack | | | | |
| Mail | | | | Einfügen nutzt TIFF |
| Finder | | | – | ⌘⇧A ist dort „Programme“ – CopyPal hat Vorrang |
| Terminal / iTerm2 | | | – | Erweitern erwartet „Kein Übergang gefunden“ bei gleichen Zeilen |
| VS Code | | | – | |
| Nachrichten | | | | Hintergrundbild kann das Erweitern stoppen |

## Tool-Konflikte

| Tool | Verhalten | Umgehung |
|---|---|---|
| Karabiner-Elements | Erzeugt synthetische Tasten. CopyPal lässt fremde synthetische Events durch, wenn sie nicht ⌘V sind. | |
| BetterTouchTool | | |
| Keyboard Maestro | | |
| TextExpander | | |
| Mos / Scroll Reverser | Drehen auch CopyPals Scroll-Ereignisse um: Erweitern läuft nach oben. | Einstellungen → Bildschirmfoto → „Scrollrichtung umkehren“ |
| CleanShot X / Shottr (eigenes ⌘⇧A o. Ä.) | Wer das Kürzel zuerst belegt, bekommt es; CopyPal zeigt dann „Von einer anderen App belegt“. | Kürzel in einer der Apps ändern |
| Raycast / Alfred (eigener Clipboard-Verlauf) | Beide Verläufe laufen parallel. CopyPals Einfügungen tragen `org.nspasteboard.source`; sensible tragen `ConcealedType`. | Den Verlauf des anderen Tools abschalten |
