import Foundation
import Security

/// App 与键盘扩展共享的数据，全部只存在本机。
///
/// 用共享钥匙串而不是 App Group：钥匙串共享组不需要在开发者网站上手动注册，
/// 云端用 API 密钥自动签名就能用；数据也是加密存储的。
final class SharedStore {
    static let shared = SharedStore()
    /// 形如 <TeamID>.<Bundle ID>.shared，由构建设置写进 Info.plist 的 EQKeychainGroup
    static let accessGroup = Bundle.main.object(forInfoDictionaryKey: "EQKeychainGroup") as? String

    private let service = "eqkeyboard"
    private let accessGroup: String?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(accessGroup: String? = SharedStore.accessGroup) {
        // 未签名的模拟器构建里前缀为空，退回到默认钥匙串组
        self.accessGroup = accessGroup.flatMap { $0.hasPrefix(".") || $0.isEmpty ? nil : $0 }
    }

    /// 匿名设备 ID，用于后端计算每日额度
    var deviceId: String {
        if let id = string("deviceId") { return id }
        let id = UUID().uuidString
        set(id, for: "deviceId")
        return id
    }

    /// Apple 登录后后端发的会话令牌，键盘用它享受订阅额度
    var sessionToken: String? {
        get { string("sessionToken") }
        set { set(newValue, for: "sessionToken") }
    }

    /// 后端用户 ID，同时作为 StoreKit 的 appAccountToken 把购买绑定到账号
    var userId: String? {
        get { string("userId") }
        set { set(newValue, for: "userId") }
    }

    /// 主 App 从截图识别出的对话，键盘读取后使用
    var importedConversation: [ChatTurn] {
        get { decode([ChatTurn].self, key: "importedConversation") ?? [] }
        set { encode(newValue.isEmpty ? nil : newValue, key: "importedConversation") }
    }

    var profile: PartnerProfile? {
        get { decode(PartnerProfile.self, key: "profile") }
        set { encode(newValue, key: "profile") }
    }

    var tone: TonePreferences {
        get { decode(TonePreferences.self, key: "tone") ?? TonePreferences() }
        set { encode(newValue, key: "tone") }
    }

    private func string(_ key: String) -> String? {
        data(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func set(_ value: String?, for key: String) {
        setData(value.map { Data($0.utf8) }, key: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = data(key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        setData(value.flatMap { try? encoder.encode($0) }, key: key)
    }

    // MARK: - Keychain

    private func query(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private func data(_ key: String) -> Data? {
        var query = query(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func setData(_ data: Data?, key: String) {
        let query = query(key)
        guard let data else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // 手机重启后首次解锁前键盘也可能被调起，用 AfterFirstUnlock
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}
