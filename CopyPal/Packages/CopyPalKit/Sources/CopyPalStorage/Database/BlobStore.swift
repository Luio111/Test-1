import Foundation

/// Large representations (images, long text) as encrypted files next to the
/// database, one file per blob, named by a UUID. Also used for the thumbnail cache.
struct BlobStore: Sendable {
    let directory: URL
    let cipher: FieldCipher

    init(directory: URL, cipher: FieldCipher) throws {
        self.directory = directory
        self.cipher = cipher
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ data: Data) throws -> UUID {
        let id = UUID()
        try write(data, id: id)
        return id
    }

    func write(_ data: Data, id: UUID) throws {
        let sealed = try cipher.seal(data, context: Self.context(id))
        try sealed.write(to: url(for: id), options: [.atomic])
    }

    func read(_ id: UUID) throws -> Data {
        let sealed = try Data(contentsOf: url(for: id))
        return try cipher.open(sealed, context: Self.context(id))
    }

    func delete(_ ids: some Sequence<UUID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: url(for: id))
        }
    }

    /// IDs of all blob files on disk (for removing orphans).
    func allIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { name in
            name.hasSuffix(".blob") ? UUID(uuidString: String(name.dropLast(5))) : nil
        })
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".blob", isDirectory: false)
    }

    private static func context(_ id: UUID) -> String {
        "blob:\(id.uuidString)"
    }
}
