# ADR 0004 – GRDB unter Linux, Einstellungen in UserDefaults

Stand: 12.10.2026 · Status: angenommen

## Kontext

1. GRDB nutzt auf Apple-Plattformen SQLite-Snapshots. Das SQLite von Ubuntu ist ohne `SQLITE_ENABLE_SNAPSHOT` gebaut, deshalb scheitert das Linken der Linux-CI.
2. CryptoKit gibt es nur auf Apple-Plattformen.
3. Der Plan (§1.6) sah eine Tabelle `app_rule` für App-Ausnahmen vor.

## Entscheidung

1. Die Linux-CI baut mit `-Xswiftc -DSQLITE_DISABLE_SNAPSHOT` und installiert `libsqlite3-dev`. Auf dem Mac ändert sich nichts.
2. `swift-crypto` ist nur unter Linux eingebunden (`condition: .when(platforms: [.linux])`). Es hat dieselbe API wie CryptoKit. Auf dem Mac nutzt die App CryptoKit selbst.
3. App-Ausnahmen (ignorieren, „⌘V halten aus“) sind Einstellungen und liegen in `UserDefaults`. Bundle-IDs sind keine Inhalte, und die Einstellungsoberfläche bindet sie direkt an. Die Tabelle `app_rule` entfällt.
4. Abhängigkeiten sind exakt festgelegt (GRDB 7.9.0, swift-crypto 3.15.1). Das generierte Xcode-Projekt checkt kein `Package.resolved` ein.
5. Statt KeyboardShortcuts verwendet CopyPal einen eigenen, kleinen Carbon-Hotkey (`GlobalHotKey`) mit eigenem Aufnahmefeld. Das spart eine Abhängigkeit.

## Folgen

- Die Speicher-Tests laufen bei jedem Push unter Linux und macOS.
- Wer lokal unter Linux testet, braucht dieselben Schalter: `swift test -Xswiftc -DSQLITE_DISABLE_SNAPSHOT`.
