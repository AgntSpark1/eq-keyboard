import Foundation
import PinyinKit
import UIKit

@MainActor
final class KeyboardModel: ObservableObject {
    enum Panel { case keys, assistant }

    @Published var panel: Panel = .keys
    @Published var suggestions: [ReplySuggestion] = []
    @Published var check: DraftCheck?
    @Published var isLoading = false
    @Published var message: String?
    @Published var tone: TonePreferences
    @Published var chineseMode = true
    @Published private(set) var composing = ""
    @Published private(set) var candidates: [Candidate] = []

    let insert: (String) -> Void
    let deleteBackward: () -> Void
    private let currentDraft: () -> String
    private let hasFullAccess: () -> Bool
    private let api = APIClient()
    private let store = SharedStore.shared
    private var engine: PinyinEngine?

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
        // 词库约 3 MB，在后台加载，加载完成前打的拼音会在之后补出候选
        Task { [weak self] in
            let engine = await Task.detached(priority: .userInitiated) { try? PinyinEngine.bundled() }.value
            self?.engine = engine
            self?.refreshCandidates()
        }
    }

    // MARK: 拼音输入

    func typeLetter(_ letter: String) {
        if chineseMode {
            composing += letter.lowercased()
            refreshCandidates()
        } else {
            insert(letter)
        }
    }

    func typeApostrophe() {
        guard chineseMode, !composing.isEmpty, composing.last != "'" else { return }
        composing += "'"
        refreshCandidates()
    }

    func tapDelete() {
        if composing.isEmpty {
            deleteBackward()
        } else {
            composing.removeLast()
            refreshCandidates()
        }
    }

    /// 空格：有拼音时上屏第一个候选，否则输入空格
    func tapSpace() {
        if composing.isEmpty {
            insert(" ")
        } else if let first = candidates.first {
            pick(first)
        } else {
            commitRaw()
        }
    }

    /// 回车：有拼音时直接上屏字母，否则换行
    func tapReturn() {
        if composing.isEmpty {
            insert("\n")
        } else {
            commitRaw()
        }
    }

    /// 标点：先把正在输入的拼音按第一个候选上屏
    func typePunctuation(_ mark: String) {
        while !composing.isEmpty, let first = candidates.first {
            pick(first)
        }
        if !composing.isEmpty { commitRaw() }
        insert(mark)
    }

    func pick(_ candidate: Candidate) {
        insert(candidate.text)
        composing = String(composing.dropFirst(candidate.consumedLength))
        while composing.first == "'" { composing.removeFirst() }
        refreshCandidates()
    }

    func toggleLanguage() {
        if !composing.isEmpty { commitRaw() }
        chineseMode.toggle()
    }

    private func commitRaw() {
        insert(composing.replacingOccurrences(of: "'", with: ""))
        composing = ""
        refreshCandidates()
    }

    private func refreshCandidates() {
        candidates = composing.isEmpty ? [] : engine?.candidates(for: composing) ?? []
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
        if mode != .reply && draft.isEmpty {
            message = String(localized: "keyboard.noDraft")
            panel = .assistant
            return
        }

        panel = .assistant
        isLoading = true
        message = nil
        suggestions = []
        check = nil
        let request = ReplyRequest(
            mode: mode,
            conversation: turns,
            draft: mode == .reply ? nil : draft,
            profile: store.profile,
            tone: tone,
            uiLanguage: APIClient.uiLanguage
        )
        Task {
            defer { isLoading = false }
            do {
                let result = try await api.suggestReplies(request)
                suggestions = result.replies
                check = result.check
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
