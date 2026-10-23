import SwiftUI
import UIKit

private enum Metrics {
    static let barHeight: CGFloat = 46
    static let keyGap: CGFloat = 6
    static let rowGap: CGFloat = 11
    static let sidePadding: CGFloat = 6
    static let keyRadius: CGFloat = 8
}

private extension Color {
    /// 字母键：浅色模式白色，深色模式中灰，接近系统键盘
    static let keyFace = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
    /// 功能键（删除、回车、中/EN 等）
    static let keyFunction = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    })
    static let keyShadow = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.4) : UIColor(white: 0.53, alpha: 1)
    })
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let needsGlobe: Bool
    let onGlobe: () -> Void
    @State private var lastMode: ReplyMode = .reply

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .frame(height: Metrics.barHeight)
            if showsExpanded {
                ExpandedCandidates(model: model)
            } else {
            switch model.panel {
            case .keys:
                if model.activeLayout == .t9 {
                    T9Keys(model: model)
                } else {
                    LetterKeys(model: model, needsGlobe: needsGlobe, onGlobe: onGlobe)
                }
            case .symbols: SymbolKeys(model: model)
            case .assistant: assistant
            }
            }
        }
        .padding(.horizontal, Metrics.sidePadding)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var showsExpanded: Bool {
        model.expanded && model.panel != .assistant
            && ((model.chineseMode && !model.composing.isEmpty) || !model.predictions.isEmpty)
    }

    /// 顶部栏：打拼音时显示候选词，刚上屏时显示联想，否则显示 AI 功能按钮
    @ViewBuilder
    private var topBar: some View {
        if model.panel != .assistant && model.chineseMode && !model.composing.isEmpty {
            CandidateBar(model: model)
        } else if model.panel != .assistant && !model.predictions.isEmpty {
            PredictionBar(model: model)
        } else {
            HStack(spacing: 8) {
                ActionChip(title: "keyboard.reply", systemImage: "sparkles", isOn: model.panel == .assistant && lastMode == .reply) {
                    lastMode = .reply
                    model.run(.reply)
                }
                ActionChip(title: "keyboard.polish", systemImage: "wand.and.stars", isOn: model.panel == .assistant && lastMode == .polish) {
                    lastMode = .polish
                    model.run(.polish)
                }
                ActionChip(title: "keyboard.check", systemImage: "checkmark.shield", isOn: model.panel == .assistant && lastMode == .check) {
                    lastMode = .check
                    model.run(.check)
                }
                Spacer(minLength: 0)
                if model.panel == .keys && model.chineseMode {
                    Button {
                        model.setLayout(model.layout == .t9 ? .qwerty : .t9)
                    } label: {
                        Text(model.layout == .t9 ? "keyboard.qwerty" : "keyboard.t9")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.keyFace.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(PressDimStyle())
                }
                if model.panel == .assistant {
                    Button {
                        model.panel = .keys
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("keyboard.back"))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ToneChip(title: "tone.humor", isOn: model.tone.humor) { model.toggleTone(\.humor) }
                ToneChip(title: "tone.warm", isOn: model.tone.warm) { model.toggleTone(\.warm) }
                ToneChip(title: "tone.direct", isOn: model.tone.direct) { model.toggleTone(\.direct) }
                ToneChip(title: "tone.brief", isOn: model.tone.brief) { model.toggleTone(\.brief) }
            }
            .padding(.horizontal, 4)
            if let last = model.session.lastTheirs {
                ContextBar(text: last, count: model.session.turns.count) { model.clearSession() }
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        if let check = model.check {
                            CheckBanner(check: check)
                        }
                        ForEach(model.suggestions) { suggestion in
                            Button {
                                model.use(suggestion, replacingDraft: lastMode != .reply)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.text).font(.body).foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(suggestion.why).font(.caption).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Color.keyFace, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// 显示这次回复针对的是对方哪句话，换了聊天对象可以一键清空
private struct ContextBar: View {
    let text: String
    let count: Int
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.bubble").font(.system(size: 12))
            Text("keyboard.context \(text)").lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Text("keyboard.turns \(count)").monospacedDigit()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("keyboard.newChat"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}

private struct ActionChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(isOn ? Color.white : Color.accentColor)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isOn ? Color.accentColor : Color.accentColor.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressDimStyle())
    }
}

private struct CheckBanner: View {
    let check: DraftCheck

    private var title: LocalizedStringKey {
        switch check.verdict {
        case .good: "check.good"
        case .adjust: "check.adjust"
        case .risky: "check.risky"
        }
    }

    private var color: Color {
        switch check.verdict {
        case .good: .green
        case .adjust: .orange
        case .risky: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold()).foregroundStyle(color)
            Text(check.note).font(.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ToneChip: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12).frame(height: 28)
                .background(isOn ? Color.accentColor.opacity(0.15) : Color.keyFace, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 按键：按下时字母键变成功能键颜色，功能键变成字母键颜色，和系统键盘一致
private struct KeyStyle: ButtonStyle {
    let isFunction: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                (isFunction != pressed ? Color.keyFunction : Color.keyFace),
                in: RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous)
            )
            .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
            .contentShape(Rectangle())
    }
}

/// 字母键盘：中文模式下字母进入拼音缓冲区，候选栏显示在顶部栏
private struct LetterKeys: View {
    @ObservedObject var model: KeyboardModel
    let needsGlobe: Bool
    let onGlobe: () -> Void
    @State private var upper = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let keyW = (width - 9 * Metrics.keyGap) / 10
            let rowH = max(36, (geo.size.height - 4 - 3 * Metrics.rowGap) / 4)
            let sideW = keyW * 1.3

            VStack(spacing: Metrics.rowGap) {
                HStack(spacing: Metrics.keyGap) {
                    letters("qwertyuiop", width: keyW)
                }
                .frame(height: rowH)

                HStack(spacing: Metrics.keyGap) {
                    letters("asdfghjkl", width: keyW)
                }
                .frame(height: rowH)

                HStack(spacing: Metrics.keyGap) {
                    Group {
                        if model.chineseMode {
                            key("'", function: true, font: .system(size: 22)) { model.typeApostrophe() }
                        } else {
                            key(systemImage: upper ? "shift.fill" : "shift") { upper.toggle() }
                        }
                    }
                    .frame(width: sideW)
                    Spacer(minLength: 0)
                    letters("zxcvbnm", width: keyW)
                    Spacer(minLength: 0)
                    key(systemImage: "delete.left") { model.tapDelete() }
                        .frame(width: sideW)
                }
                .frame(height: rowH)

                HStack(spacing: Metrics.keyGap) {
                    if needsGlobe {
                        key(systemImage: "globe", action: onGlobe).frame(width: keyW)
                    }
                    key("123", function: true, font: .system(size: 16)) { model.panel = .symbols }
                        .frame(width: keyW * 1.1)
                    key(model.chineseMode ? "中" : "EN", function: true, font: .system(size: 17)) { model.toggleLanguage() }
                        .frame(width: keyW * 1.1)
                    key(model.chineseMode ? "，" : ",", font: .system(size: 20)) {
                        model.typePunctuation(model.chineseMode ? "，" : ",")
                    }
                    .frame(width: keyW)
                    key(String(localized: "keyboard.space"), font: .system(size: 16)) { model.tapSpace() }
                    key(model.chineseMode ? "。" : ".", font: .system(size: 20)) {
                        model.typePunctuation(model.chineseMode ? "。" : ".")
                    }
                    .frame(width: keyW)
                    key(systemImage: "return") { model.tapReturn() }
                        .frame(width: needsGlobe ? keyW * 1.5 : keyW * 1.9)
                }
                .frame(height: rowH)
            }
            .padding(.top, 4)
            .frame(width: width, alignment: .top)
        }
    }

    @ViewBuilder
    private func letters(_ row: String, width: CGFloat) -> some View {
        ForEach(Array(row), id: \.self) { ch in
            let letter = upper && !model.chineseMode ? String(ch).uppercased() : String(ch)
            key(letter, font: .system(size: 23)) { model.typeLetter(letter) }
                .frame(width: width)
        }
    }

    private func key(_ title: String, function: Bool = false, font: Font, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(font)
        }
        .buttonStyle(KeyStyle(isFunction: function))
    }

    private func key(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 18, weight: .regular))
        }
        .buttonStyle(KeyStyle(isFunction: true))
    }
}

private struct CandidateBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.composingDisplay)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .frame(height: 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(model.candidates.prefix(60).enumerated()), id: \.offset) { index, candidate in
                        Button {
                            model.pick(candidate)
                        } label: {
                            Text(candidate.text)
                                .font(.system(size: 20, weight: index == 0 ? .semibold : .regular))
                                .foregroundStyle(index == 0 ? Color.accentColor : Color.primary)
                                .padding(.horizontal, 8)
                                .frame(height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressDimStyle())
                    }
                }
            }
            .frame(height: 30)
            .noScrollEdgeBlur()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
        .overlay(alignment: .trailing) {
            ExpandButton(model: model)
        }
    }
}

/// 候选栏、联想栏右边的展开 / 收起按钮
private struct ExpandButton: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Button {
            model.toggleExpanded()
        } label: {
            Image(systemName: model.expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: Metrics.barHeight)
                .background(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5, height: 24)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(Text(model.expanded ? "keyboard.collapse" : "keyboard.expand"))
    }
}

/// 展开后的候选面板：所有候选词（没在打拼音时是联想词）排成网格，右边是收起、删除、重输
private struct ExpandedCandidates: View {
    @ObservedObject var model: KeyboardModel

    private var showsCandidates: Bool { model.chineseMode && !model.composing.isEmpty }

    var body: some View {
        GeometryReader { geo in
            let sideW = geo.size.width * 0.17
            let rowH = max(36, (geo.size.height - 4 - 3 * Metrics.rowGap) / 4)

            HStack(alignment: .top, spacing: Metrics.keyGap) {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 54), spacing: Metrics.keyGap)],
                        spacing: Metrics.keyGap
                    ) {
                        if showsCandidates {
                            ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                                cell(candidate.text, highlighted: index == 0) { model.pick(candidate) }
                            }
                        } else {
                            ForEach(model.predictions, id: \.self) { word in
                                cell(word, highlighted: false) { model.pickPrediction(word) }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity)
                .noScrollEdgeBlur()

                VStack(spacing: Metrics.rowGap) {
                    KeyCap(systemImage: "chevron.up", function: true) { model.toggleExpanded() }
                        .frame(height: rowH)
                    KeyCap(systemImage: "delete.left", function: true) { model.tapDelete() }
                        .frame(height: rowH)
                    if showsCandidates {
                        KeyCap(title: String(localized: "keyboard.reset"), function: true, font: .system(size: 16)) {
                            model.clearComposing()
                        }
                        .frame(height: rowH)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: sideW)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .padding(.top, 4)
        }
    }

    private func cell(_ text: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 19, weight: highlighted ? .semibold : .regular))
                .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.keyFace, in: RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous))
                .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
    }
}

private extension View {
    /// iOS 26 起滚动视图边缘会自动加模糊，候选栏很矮，会把整排候选字糊掉
    @ViewBuilder
    func noScrollEdgeBlur() -> some View {
        // 这个 API 只在 iOS 26 SDK（Xcode 26）里有，CI 的 Xcode 16 编译不到
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// 一个按键，供九键和符号键盘共用
private struct KeyCap: View {
    var title: String?
    var subtitle: String?
    var systemImage: String?
    var function = false
    var font: Font = .system(size: 20)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 18))
            } else {
                VStack(spacing: 0) {
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(title ?? "").font(font)
                }
            }
        }
        .buttonStyle(KeyStyle(isFunction: function))
    }
}

/// 九键拼音：左侧是音节（没在打字时是常用标点），中间 2-9 数字键，右侧删除、重输、句号
private struct T9Keys: View {
    @ObservedObject var model: KeyboardModel

    private let grid: [[(Character, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
    ]
    private let punctuation = ["，", "。", "？", "！", "…", "~", "、"]

    var body: some View {
        GeometryReader { geo in
            let sideW = geo.size.width * 0.17
            let centerW = (geo.size.width - 2 * sideW - 4 * Metrics.keyGap) / 3
            let rowH = max(36, (geo.size.height - 4 - 3 * Metrics.rowGap) / 4)

            VStack(spacing: Metrics.rowGap) {
                HStack(alignment: .top, spacing: Metrics.keyGap) {
                    sideColumn
                        .frame(width: sideW, height: rowH * 3 + Metrics.rowGap * 2)
                    VStack(spacing: Metrics.rowGap) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: Metrics.keyGap) {
                                ForEach(grid[row], id: \.0) { digit, letters in
                                    if digit == "1" {
                                        KeyCap(title: "，", subtitle: "1", font: .system(size: 20)) {
                                            model.typePunctuation("，")
                                        }
                                        .frame(width: centerW)
                                    } else {
                                        KeyCap(title: letters, subtitle: String(digit), font: .system(size: 18, weight: .medium)) {
                                            model.typeDigit(digit)
                                        }
                                        .frame(width: centerW)
                                    }
                                }
                            }
                            .frame(height: rowH)
                        }
                    }
                    VStack(spacing: Metrics.rowGap) {
                        KeyCap(systemImage: "delete.left", function: true) { model.tapDelete() }
                            .frame(height: rowH)
                        KeyCap(title: String(localized: "keyboard.reset"), function: true, font: .system(size: 16)) {
                            model.clearComposing()
                        }
                        .frame(height: rowH)
                        KeyCap(title: "。", font: .system(size: 20)) { model.typePunctuation("。") }
                            .frame(height: rowH)
                    }
                    .frame(width: sideW)
                }

                HStack(spacing: Metrics.keyGap) {
                    KeyCap(title: "123", function: true, font: .system(size: 16)) { model.panel = .symbols }
                        .frame(width: sideW)
                    KeyCap(title: "中", function: true, font: .system(size: 17)) { model.toggleLanguage() }
                        .frame(width: centerW)
                    KeyCap(title: String(localized: "keyboard.space"), font: .system(size: 16)) { model.tapSpace() }
                    KeyCap(systemImage: "return", function: true) { model.tapReturn() }
                        .frame(width: sideW)
                }
                .frame(height: rowH)
            }
            .padding(.top, 4)
        }
    }

    private var sideColumn: some View {
        let items = model.composing.isEmpty ? punctuation : model.t9Syllables
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    Button {
                        if model.composing.isEmpty {
                            model.typePunctuation(item)
                        } else {
                            model.selectSyllable(item)
                        }
                    } label: {
                        Text(item)
                            .font(.system(size: 16, weight: model.t9Syllable == item ? .semibold : .regular))
                            .foregroundStyle(model.t9Syllable == item ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressDimStyle())
                }
            }
        }
        .noScrollEdgeBlur()
        .background(Color.keyFunction, in: RoundedRectangle(cornerRadius: Metrics.keyRadius, style: .continuous))
        .shadow(color: .keyShadow, radius: 0, x: 0, y: 1)
    }
}

/// 数字和符号键盘
private struct SymbolKeys: View {
    @ObservedObject var model: KeyboardModel

    private var rows: [[String]] {
        if model.chineseMode {
            return [
                "1234567890".map(String.init),
                ["-", "/", "：", "；", "（", "）", "¥", "@", "“", "”"],
                ["。", "，", "、", "？", "！", "…", "~"],
            ]
        }
        return [
            "1234567890".map(String.init),
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
            [".", ",", "?", "!", "'", "#", "%"],
        ]
    }

    var body: some View {
        GeometryReader { geo in
            let keyW = (geo.size.width - 9 * Metrics.keyGap) / 10
            let rowH = max(36, (geo.size.height - 4 - 3 * Metrics.rowGap) / 4)

            VStack(spacing: Metrics.rowGap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: Metrics.keyGap) {
                        ForEach(rows[row], id: \.self) { symbol in
                            KeyCap(title: symbol, font: .system(size: 21)) { model.typePunctuation(symbol) }
                                .frame(width: keyW)
                        }
                    }
                    .frame(height: rowH)
                }
                HStack(spacing: Metrics.keyGap) {
                    Spacer(minLength: 0)
                    ForEach(rows[2], id: \.self) { symbol in
                        KeyCap(title: symbol, font: .system(size: 21)) { model.typePunctuation(symbol) }
                            .frame(width: keyW * 1.15)
                    }
                    Spacer(minLength: 0)
                    KeyCap(systemImage: "delete.left", function: true) { model.tapDelete() }
                        .frame(width: keyW * 1.3)
                }
                .frame(height: rowH)
                HStack(spacing: Metrics.keyGap) {
                    KeyCap(title: model.chineseMode ? "拼音" : "ABC", function: true, font: .system(size: 16)) {
                        model.panel = .keys
                    }
                    .frame(width: keyW * 2.2)
                    KeyCap(title: String(localized: "keyboard.space"), font: .system(size: 16)) { model.tapSpace() }
                    KeyCap(systemImage: "return", function: true) { model.tapReturn() }
                        .frame(width: keyW * 2.2)
                }
                .frame(height: rowH)
            }
            .padding(.top, 4)
        }
    }
}

/// 联想栏：刚上屏的字后面可能接的字词，最右边可以收起回到 AI 按钮
private struct PredictionBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.predictions, id: \.self) { word in
                        Button {
                            model.pickPrediction(word)
                        } label: {
                            Text(word)
                                .font(.system(size: 19))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 9)
                                .frame(height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressDimStyle())
                    }
                }
            }
            .noScrollEdgeBlur()
            ExpandButton(model: model)
            Button {
                model.dismissPredictions()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressDimStyle())
        }
    }
}
