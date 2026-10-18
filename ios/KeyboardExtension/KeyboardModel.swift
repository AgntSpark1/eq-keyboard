import Foundation
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    enum Panel { case keys, assistant }

    @Published var panel: Panel = .keys
    @Published var suggestions: [ReplySuggestion] = []
    @Published var isLoading = false
    @Published var message: String?
    @Published var tone: TonePreferences

    let insert: (String) -> Void
    let deleteBackward: () -> Void
    private let currentDraft: () -> String
    private let hasFullAccess: () -> Bool
    private let api = APIClient()
    private let store = SharedStore.shared

    init(
        insert: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        currentDraft: @escaping () -> String,
        hasFullAccess: @escaping () -> Bool
    ) {
        self.insert = insert
        self.deleteBackward = deleteBackward
        self.currentDraft = currentDraft
        self.hasFullAccess = hasFullAccess
        self.tone = SharedStore.shared.tone
    }

    func toggleTone(_ keyPath: WritableKeyPath<TonePreferences, Bool>) {
        tone[keyPath: keyPath].toggle()
        store.tone = tone
    }

    /// 对话来源：优先使用主 App 导入的截图对话，否则把剪贴板内容当作对方的消息
    private func conversation() -> [ChatTurn] {
        let imported = store.importedConversation
        if !imported.isEmpty { return imported }
        guard let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.isEmpty else { return [] }
        return pasted
            .split(separator: "\n")
            .map { ChatTurn(speaker: .them, text: String($0)) }
    }

    func run(_ mode: ReplyMode) {
        guard hasFullAccess() else {
            message = String(localized: "keyboard.needFullAccess")
            panel = .assistant
            return
        }
        let turns = conversation()
        guard !turns.isEmpty else {
            message = String(localized: "keyboard.noConversation")
            panel = .assistant
            return
        }
        let draft = currentDraft().trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .polish && draft.isEmpty {
            message = String(localized: "keyboard.noDraft")
            panel = .assistant
            return
        }

        panel = .assistant
        isLoading = true
        message = nil
        suggestions = []
        let request = ReplyRequest(
            mode: mode,
            conversation: turns,
            draft: mode == .polish ? draft : nil,
            profile: store.profile,
            tone: tone,
            uiLanguage: APIClient.uiLanguage
        )
        Task {
            defer { isLoading = false }
            do {
                suggestions = try await api.suggestReplies(request).replies
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func use(_ suggestion: ReplySuggestion, replacingDraft: Bool) {
        if replacingDraft {
            for _ in currentDraft() { deleteBackward() }
        }
        insert(suggestion.text)
        panel = .keys
    }

    /// 用过的截图对话清掉，避免下一次误用
    func clearImported() {
        store.importedConversation = []
    }
}
