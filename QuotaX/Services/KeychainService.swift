import Foundation
import CryptoKit

// MARK: - 本地凭据存储（AES-GCM 加密）
/// API Key / Token 使用 AES-256-GCM 加密后保存在本地文件
/// 加密密钥派生自机器硬件 UUID，仅当前设备可解密
enum KeychainService {

    private static let dirName = "QuotaX"
    private static let fileName = "credentials.enc"

    // MARK: - 存取接口

    static func save(key: String, value: String) throws {
        var store = loadStore()
        store[key] = value
        try saveStore(store)
    }

    static func load(key: String) -> String? {
        loadStore()[key]
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        var store = loadStore()
        guard store.removeValue(forKey: key) != nil else { return true }
        return (try? saveStore(store)) != nil
    }

    static func exists(key: String) -> Bool { load(key: key) != nil }

    // MARK: - AES-GCM 加密/解密

    private static func loadStore() -> [String: String] {
        let url = storageURL()
        guard let ciphertext = try? Data(contentsOf: url) else { return [:] }
        guard let plaintext = try? decrypt(ciphertext) else { return [:] }
        guard let dict = try? JSONDecoder().decode([String: String].self, from: plaintext) else { return [:] }
        return dict
    }

    private static func saveStore(_ store: [String: String]) throws {
        let json = try JSONEncoder().encode(store)
        let ciphertext = try encrypt(json)
        try ciphertext.write(to: storageURL(), options: .atomic)

        // 设置文件权限为 600（仅当前用户可读写）
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: storageURL().path
        )
    }

    private static func encrypt(_ data: Data) throws -> Data {
        let key = deriveKey()
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw CryptoError.encryptionFailed
        }
        return combined
    }

    private static func decrypt(_ data: Data) throws -> Data {
        let key = deriveKey()
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - 密钥派生（基于机器硬件 UUID）

    /// 从硬件 UUID 派生 AES-256 对称密钥，仅当前设备可解密
    private static func deriveKey() -> SymmetricKey {
        let seed = hardwareUUID()
        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }

    /// 获取当前 Mac 的硬件 UUID
    private static func hardwareUUID() -> String {
        let service = IOServiceMatching("IOPlatformExpertDevice")
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, service, &iterator) == KERN_SUCCESS else {
            return "QuotaX-fallback-key-seed"
        }

        defer { IOObjectRelease(iterator) }
        let device = IOIteratorNext(iterator)
        defer { IOObjectRelease(device) }

        guard device != 0,
              let uuid = IORegistryEntryCreateCFProperty(
                  device, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
              )?.takeRetainedValue() as? String else {
            return "QuotaX-fallback-key-seed"
        }

        return uuid
    }

    // MARK: - 文件路径

    private static func storageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(dirName)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(fileName)
    }
}

private enum CryptoError: LocalizedError {
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "加密失败"
        }
    }
}
