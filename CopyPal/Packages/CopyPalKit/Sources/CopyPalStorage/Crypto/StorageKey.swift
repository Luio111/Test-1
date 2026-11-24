import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// The 256-bit key everything stored is encrypted with. Kept in the Keychain (this
/// device only), never written to disk in the clear.
public struct StorageKey: Sendable, Equatable {
    public let data: Data

    public init(data: Data) throws {
        guard data.count == 32 else { throw StorageError.invalidKey }
        self.data = data
    }

    public static func generate() -> StorageKey {
        let key = SymmetricKey(size: .bits256)
        // Exactly 32 bytes by construction.
        return try! StorageKey(data: key.withUnsafeBytes { Data($0) })
    }

    var symmetricKey: SymmetricKey {
        SymmetricKey(data: data)
    }

    /// Separate key for duplicate fingerprints, so a fingerprint reveals nothing
    /// about the encryption key and cannot be guessed from the plain text.
    func derivedKey(purpose: String) -> Data {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: symmetricKey,
            info: Data("CopyPal \(purpose)".utf8),
            outputByteCount: 32
        )
        return derived.withUnsafeBytes { Data($0) }
    }
}

/// AES-GCM with the record it belongs to as additional authenticated data, so an
/// encrypted value cannot be moved to another record or field unnoticed.
struct FieldCipher: Sendable {
    private let keyData: Data
    private let fingerprintKeyData: Data

    init(key: StorageKey) {
        keyData = key.data
        fingerprintKeyData = key.derivedKey(purpose: "fingerprint")
    }

    func seal(_ plaintext: Data, context: String) throws -> Data {
        do {
            let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: keyData), authenticating: Data(context.utf8))
            guard let combined = box.combined else { throw StorageError.encryptionFailed }
            return combined
        } catch let error as StorageError {
            throw error
        } catch {
            throw StorageError.encryptionFailed
        }
    }

    func open(_ sealed: Data, context: String) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData), authenticating: Data(context.utf8))
        } catch {
            throw StorageError.decryptionFailed
        }
    }

    /// HMAC-SHA256 of the canonical content: equal content → equal fingerprint.
    func fingerprint(_ source: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: source, using: SymmetricKey(data: fingerprintKeyData)))
    }
}

public enum StorageError: Error, Sendable, Equatable {
    case invalidKey
    case encryptionFailed
    case decryptionFailed
    case keychain(status: Int32)
    case notFound
}
