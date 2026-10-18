import Foundation

/// App 与键盘扩展通过 App Group 共享的数据，全部只存在本机。
final class SharedStore {
    static let shared = SharedStore()
    /// 由构建设置 EQ_BUNDLE_ID 生成，写在 Info.plist 的 EQAppGroup
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "EQAppGroup") as? String ?? "group.com.yonghuizhang.eqkeyboard"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroup)) {
        self.defaults = defaults ?? .standard
    }

    /// 匿名设备 ID，用于后端计算每日额度
    var deviceId: String {
        if let id = defaults.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "deviceId")
        return id
    }

    /// Apple 登录后后端发的会话令牌，键盘用它享受订阅额度
    var sessionToken: String? {
        get { defaults.string(forKey: "sessionToken") }
        set { defaults.set(newValue, forKey: "sessionToken") }
    }

    /// 后端用户 ID，同时作为 StoreKit 的 appAccountToken 把购买绑定到账号
    var userId: String? {
        get { defaults.string(forKey: "userId") }
        set { defaults.set(newValue, forKey: "userId") }
    }

    /// 主 App 从截图识别出的对话，键盘读取后使用
    var importedConversation: [ChatTurn] {
        get { decode([ChatTurn].self, key: "importedConversation") ?? [] }
        set { encode(newValue, key: "importedConversation") }
    }

    var profile: PartnerProfile? {
        get { decode(PartnerProfile.self, key: "profile") }
        set { encode(newValue, key: "profile") }
    }

    var tone: TonePreferences {
        get { decode(TonePreferences.self, key: "tone") ?? TonePreferences() }
        set { encode(newValue, key: "tone") }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? encoder.encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
