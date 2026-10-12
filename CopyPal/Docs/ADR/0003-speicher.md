# 0003 – Speicher: GRDB + verschlüsselte Blobs

**Kontext.** Der Verlauf enthält potenziell sensible Daten. Er soll lokal verschlüsselt liegen und später optional per iCloud synchronisiert werden können, ohne dass sensible Einträge je hochgeladen werden.

**Entscheidung.** SQLite über GRDB, große Inhalte als Dateien; Inhalte, Vorschauen und Miniaturen werden mit AES-GCM (CryptoKit) verschlüsselt, der Schlüssel liegt in der Keychain. Details: ROADMAP §1.5–1.6.

**Verworfen.** SwiftData: kein feldgenaues Verschlüsseln, unkontrollierter CloudKit-Sync, unter macOS 14 noch unausgereift.

**Folgen.** Mehr Boilerplate (Records, Migrationen); dafür testbar unter `swift test` und volle Kontrolle über Sync (CKSyncEngine in v2).
