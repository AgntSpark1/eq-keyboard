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
            switch model.panel {
            case .keys: LetterKeys(model: model, needsGlobe: needsGlobe, onGlobe: onGlobe)
            case .assistant: assistant
            }
        }
        .padding(.horizontal, Metrics.sidePadding)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 顶部栏：打拼音时显示候选词，否则显示 AI 功能按钮
    @ViewBuilder
    private var topBar: some View {
        if model.panel == .keys && model.chineseMode && !model.composing.isEmpty {
            CandidateBar(model: model)
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
                                model.clearImported()
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
                        key(systemImage: "globe", action: onGlobe).frame(width: keyW * 1.1)
                    }
                    key(model.chineseMode ? "中" : "EN", function: true, font: .system(size: 17)) { model.toggleLanguage() }
                        .frame(width: needsGlobe ? keyW * 1.1 : sideW)
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
                        .frame(width: keyW * 1.9)
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
            Text(model.composing)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .frame(height: 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
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
    }
}

private extension View {
    /// iOS 26 起滚动视图边缘会自动加模糊，候选栏很矮，会把整排候选字糊掉
    @ViewBuilder
    func noScrollEdgeBlur() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
