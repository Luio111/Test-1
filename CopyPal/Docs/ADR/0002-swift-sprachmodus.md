# 0002 – Swift-Sprachmodus

**Kontext.** Swift 6 macht Datenrennen zu Compilerfehlern. Der AppKit-/CoreGraphics-Code (Event-Tap, Pasteboard, Fenster) kann nur auf macOS kompiliert werden; jeder Fehler kostet dort einen CI-Durchlauf (privates Repo, macOS-Minuten zählen zehnfach).

**Entscheidung.**
- `CopyPalCore`, `CopyPalStorage`, `CopyPalServices`: Swift-6-Sprachmodus.
- `CopyPalSystem` und das App-Target: Swift-5-Modus mit vollständiger Concurrency-Prüfung (`StrictConcurrency` / `SWIFT_STRICT_CONCURRENCY = complete`). Probleme erscheinen als Warnungen.
- UI- und Systemtypen werden explizit mit `@MainActor` annotiert.

**Folgen.**
- Warnungen werden wie Fehler behandelt und vor dem Merge behoben.
- Spätestens in M8 (Härtung) werden System und App auf Swift 6 umgestellt.
