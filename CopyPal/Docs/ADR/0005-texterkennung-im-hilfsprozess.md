# 0005 – Texterkennung im Hilfsprozess (XPC)

**Kontext.** Seit M12 liest CopyPal Text in Bildern mit Vision (durchsuchbar, sensible Inhalte, ⇧⏎). Vision lädt dafür Modelle und gibt sie bis zum Prozessende nicht mehr frei: Im Selbsttest stieg der Speicher von 51 auf 121–129 MB (ROADMAP R32). Ziel sind unter 50 MB im Leerlauf (§4.4).

**Entscheidung.** Vision läuft in einem XPC-Dienst im App-Bundle (`Contents/XPCServices/CopyPalTextRecognition.xpc`, Quellen in `XPCServices/TextRecognition`). Die App (`TextRecognitionClient`) hält die Verbindung offen, solange Bilder anstehen, und schließt sie 5 s nach der letzten Antwort. Der Dienst beendet sich, sobald keine Verbindung mehr offen ist, und mit ihm verschwinden die Modelle. Die Priorität des Aufrufers geht mit: Hintergrund-Erkennung als „utility“, ⇧⏎ als „user-initiated“.

- Endet der Dienst während einer Anfrage (er schloss gerade, oder ein Bild brachte ihn zum Absturz), gibt es einen zweiten Versuch; danach gilt das Bild als ohne Text. Ein Absturz trifft so nie die App.
- Startet der Dienst gar nicht, liest die App selbst (wie vorher). Die Funktion fällt so nie einfach weg; der Selbsttest prüft, dass in der CI der Dienst arbeitet.
- Keine Antwort nach 60 s: Die App beendet den Dienst.

**Verworfen.** Ein Kommandozeilen-Helfer über `Process` und Pipes: eigenes Protokoll, eigenes Lebenszeit-Management, kein Neustart durch launchd. Vision im App-Prozess mit Aufräumen: Vision bietet kein Entladen der Modelle.

**Folgen.** Ein zweites Target in `project.yml` (signiert und mit Hardened Runtime wie die App, wird beim Archivieren mit signiert). Das erste Bild nach einer Pause wartet kurz auf den Start des Dienstes und das Laden der Modelle. Der Dienst sieht nur Bilddaten, schreibt nichts und protokolliert keine Inhalte.
