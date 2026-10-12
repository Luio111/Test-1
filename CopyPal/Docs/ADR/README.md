# Architekturentscheidungen (ADR)

Kurze Protokolle wichtiger Entscheidungen: Kontext, Entscheidung, Folgen.

| Nr. | Entscheidung | Status |
|---|---|---|
| [0001](0001-projektstruktur.md) | XcodeGen + lokales Swift-Package, macOS-Code Linux-kompilierbar | angenommen |
| [0002](0002-swift-sprachmodus.md) | Swift 6 für plattformneutrale Module, Swift 5 + strikte Prüfung für AppKit-Code | angenommen |
| [0003](0003-speicher.md) | GRDB (SQLite) + verschlüsselte Blobs statt SwiftData | umgesetzt (M3) |
| [0004](0004-grdb-linux-und-einstellungen.md) | GRDB unter Linux, Einstellungen in UserDefaults, eigener Hotkey | angenommen |
