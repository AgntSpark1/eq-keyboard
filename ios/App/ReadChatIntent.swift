import AppIntents
import UIKit

/// 给“快捷指令”用：截屏 → 识别聊天 → 交给键盘。配合“轻点背面”，在微信里敲两下手机背面
/// 就能把整屏对话交给键盘，不用切出微信。截图只在手机上识别，不会上传。
struct ReadChatScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "intent.read.title"
    static let description = IntentDescription("intent.read.description")
    static let openAppWhenRun = false

    // supportedContentTypes 需要 iOS 18；不是图片时下面会返回“没有识别到”
    @Parameter(title: "intent.read.screenshot")
    var screenshot: IntentFile

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image = UIImage(data: screenshot.data) else {
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.read.none")))
        }
        let turns = try await ChatOCR.recognize(image)
        guard !turns.isEmpty else {
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.read.none")))
        }
        SharedStore.shared.importedConversation = turns
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.read.done \(turns.count)")))
    }
}
