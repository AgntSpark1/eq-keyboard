import Foundation

/// 发送前在手机上抹掉明显的个人信息，后端还会再做一遍。
enum Redactor {
    private static let patterns: [(String, String)] = [
        (#"[\w.+-]+@[\w-]+\.[\w.-]+"#, "[邮箱]"),
        (#"\b\d{17}[\dXx]\b"#, "[证件号]"),
        (#"(?<!\d)1[3-9]\d{9}(?!\d)"#, "[手机号]"),
        (#"\+?\d[\d\s-]{8,}\d"#, "[电话]"),
    ]

    static func redact(_ text: String) -> String {
        patterns.reduce(text) { out, pair in
            out.replacingOccurrences(of: pair.0, with: pair.1, options: .regularExpression)
        }
    }
}
