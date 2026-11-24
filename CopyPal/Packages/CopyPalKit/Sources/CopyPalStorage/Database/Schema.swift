import GRDB

/// Database schema (ROADMAP §1.6). Only IDs, timestamps, kind, flags, sizes and the
/// source app's bundle ID are stored in the clear; everything with content ends in
/// `_enc` and is AES-GCM encrypted. Times are seconds since 1970 (REAL) so the order
/// of quick successive copies is exact. Per-app rules (ignore, hold off) are settings
/// and live in UserDefaults, not here.
enum Schema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clip_item") { t in
                t.primaryKey("id", .text)
                t.column("created_at", .double).notNull()
                t.column("last_used_at", .double).notNull()
                t.column("modified_at", .double).notNull()
                t.column("deleted_at", .double)
                t.column("kind", .text).notNull()
                t.column("fingerprint", .blob)
                t.column("preview_enc", .blob)
                t.column("source_bundle_id", .text)
                t.column("origin", .text).notNull()
                t.column("sensitivity", .text)
                t.column("expires_at", .double)
                t.column("local_only", .boolean).notNull().defaults(to: false)
                t.column("pinned_at", .double)
                t.column("pin_label_enc", .blob)
                t.column("pin_sort", .double)
                t.column("byte_size", .integer).notNull().defaults(to: 0)
                t.column("use_count", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "clip_item_last_used", on: "clip_item", columns: ["deleted_at", "last_used_at"])
            try db.create(index: "clip_item_fingerprint", on: "clip_item", columns: ["fingerprint"])

            try db.create(table: "clip_representation") { t in
                t.primaryKey("id", .text)
                t.column("item_id", .text).notNull().indexed().references("clip_item", onDelete: .cascade)
                t.column("item_index", .integer).notNull()
                t.column("position", .integer).notNull()
                t.column("uti", .text).notNull()
                t.column("data_enc", .blob)
                t.column("blob_id", .text)
                t.column("byte_size", .integer).notNull()
            }

            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob)
            }
        }
        return migrator
    }
}
