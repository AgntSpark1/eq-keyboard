import Foundation
import PinyinKit
import UIKit

enum KeyboardLayout: String {
    case qwerty, t9
}

@MainActor
final class KeyboardModel: ObservableObject {
    enum Panel { case keys, symbols, assistant }
    static let layoutKey = "keyboardLayout"

    @Published var panel: Panel = .keys
    @Published var suggestions: [ReplySuggestion] = []
    @Published var check: DraftCheck?
    @Published var isLoading = false
    @Published var message: String?
    @Published var tone: TonePreferences
    @Published var chineseMode = true
    @Published private(set) var composing = ""
    @Published private(set) var candidates: [Candidate] = []
    /// 候选栏上方显示的拼音；九键时是第一个候选的拼音
    @Published private(set) var composingDisplay = ""
    /// 九键左侧可选的音节
    @Published private(set) var t9Syllables: [String] = []
    @Published private(set) var t9Syllable: String?
    /// 输入联想：上屏后显示在顶部栏
    @Published private(set) var predictions: [String] = []
    @Published private(set) var layout: KeyboardLayout =
        KeyboardLayout(rawValue: UserDefaults.standard.string(forKey: KeyboardModel.layoutKey) ?? "") ?? .qwerty
    /// 候选或联想展开成整块面板，盖住按键区
    @Published private(set) var expanded = false
    /// 最近上屏的几个字，用来联想
    private var recent = ""
    /// 最近上屏的一个词，用来记住用户自己的接续习惯
    private var lastWord = ""
    private let memory = InputMemory()

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

    /// 九键只用于中文；英文始终是全键盘
    var activeLayout: KeyboardLayout { chineseMode ? layout : .qwerty }

    func setLayout(_ newLayout: KeyboardLayout) {
        guard newLayout != layout else { return }
        clearComposing()
        layout = newLayout
        UserDefaults.standard.set(newLayout.rawValue, forKey: Self.layoutKey)
    }

    func typeLetter(_ letter: String) {
        predictions = []
        if chineseMode {
            composing += letter.lowercased()
            refreshCandidates()
        } else {
            insert(letter)
        }
    }

    /// 九键数字 2-9
    func typeDigit(_ digit: Character) {
        predictions = []
        composing.append(digit)
        refreshCandidates()
    }

    /// 九键左侧选定第一个音节，候选只保留这个读音开头的词
    func selectSyllable(_ syllable: String) {
        t9Syllable = t9Syllable == syllable ? nil : syllable
        refreshCandidates()
    }

    func typeApostrophe() {
        guard chineseMode, !composing.isEmpty, composing.last != "'" else { return }
        composing += "'"
        refreshCandidates()
    }

    func tapDelete() {
        predictions = []
        if composing.isEmpty {
            deleteBackward()
            recent = String(recent.dropLast())
        } else if t9Syllable != nil {
            t9Syllable = nil
            refreshCandidates()
        } else {
            composing.removeLast()
            refreshCandidates()
        }
    }

    /// 九键“重输”：清空正在打的拼音
    func clearComposing() {
        composing = ""
        t9Syllable = nil
        refreshCandidates()
    }

    /// 空格：有拼音时上屏第一个候选，否则输入空格
    func tapSpace() {
        if composing.isEmpty {
            predictions = []
            insert(" ")
            recent = ""
            lastWord = ""
        } else if let first = candidates.first {
            pick(first)
        } else {
            commitRaw()
        }
    }

    /// 回车：有拼音时直接上屏字母，否则换行
    func tapReturn() {
        predictions = []
        if composing.isEmpty {
            insert("\n")
            recent = ""
            lastWord = ""
        } else {
            commitRaw()
        }
    }

    /// 标点和符号：先把正在输入的拼音按第一个候选上屏
    func typePunctuation(_ mark: String) {
        while !composing.isEmpty, let first = candidates.first {
            pick(first)
        }
        if !composing.isEmpty { commitRaw() }
        predictions = []
        insert(mark)
        recent = ""
        lastWord = ""
    }

    func pick(_ candidate: Candidate) {
        memory.recordPick(candidate.text, input: memoryKey(String(composing.prefix(candidate.consumedLength))))
        expanded = false
        commit(candidate.text)
        composing = String(composing.dropFirst(candidate.consumedLength))
        while composing.first == "'" { composing.removeFirst() }
        t9Syllable = nil
        refreshCandidates()
        if composing.isEmpty { refreshPredictions() }
    }

    func dismissPredictions() {
        predictions = []
        expanded = false
    }

    func toggleExpanded() {
        expanded.toggle()
    }

    /// 选联想词：直接上屏，再接着联想
    func pickPrediction(_ word: String) {
        expanded = false
        commit(word)
        refreshPredictions()
    }

    func toggleLanguage() {
        if !composing.isEmpty { commitRaw() }
        predictions = []
        chineseMode.toggle()
    }

    private func commit(_ text: String) {
        memory.recordNext(text, after: lastWord)
        lastWord = text
        insert(text)
        recent = String((recent + text).suffix(6))
    }

    private func commitRaw() {
        let raw = activeLayout == .t9 ? composingDisplay : composing
        insert(raw.replacingOccurrences(of: "'", with: ""))
        composing = ""
        t9Syllable = nil
        recent = ""
        lastWord = ""
        refreshCandidates()
    }

    private func refreshPredictions() {
        let base = engine?.predictions(after: recent) ?? []
        predictions = memory.predictions(after: lastWord, base: base)
    }

    /// 用户词频的键：全键是去掉分隔符的拼音，九键是数字串（加上选定的音节）
    private func memoryKey(_ input: String) -> String {
        if activeLayout == .t9 { return "t9:" + (t9Syllable.map { $0 + "|" } ?? "") + input }
        return input.replacingOccurrences(of: "'", with: "")
    }

    private func refreshCandidates() {
        refreshRawCandidates()
        guard candidates.count > 1 else { return }
        let ranked = memory.rank(candidates.map(\.text), input: memoryKey(composing))
        guard ranked != candidates.map(\.text) else { return }
        var byText: [String: Candidate] = [:]
        for candidate in candidates where byText[candidate.text] == nil { byText[candidate.text] = candidate }
        candidates = ranked.compactMap { byText[$0] }
    }

    private func refreshRawCandidates() {
        guard !composing.isEmpty, let engine else {
            candidates = []
            t9Syllables = []
            composingDisplay = composing
            return
        }
        if activeLayout == .t9 {
            let results = engine.t9Candidates(for: composing, firstSyllable: t9Syllable)
            candidates = results.map { Candidate(text: $0.text, consumedLength: $0.consumedLength) }
            t9Syllables = engine.t9Syllables(for: composing)
            if let first = results.first, first.consumedLength == composing.count {
                composingDisplay = first.pinyin
            } else if let t9Syllable {
                composingDisplay = t9Syllable + "'" + composing.dropFirst(t9Syllable.count)
            } else {
                composingDisplay = composing
            }
        } else {
            candidates = engine.candidates(for: composing)
            t9Syllables = []
            composingDisplay = composing
        }
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
