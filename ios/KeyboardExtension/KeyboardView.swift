import SwiftUI

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let needsGlobe: Bool
    let onGlobe: () -> Void
    @State private var lastMode: ReplyMode = .reply

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            switch model.panel {
            case .keys: LetterKeys(model: model, needsGlobe: needsGlobe, onGlobe: onGlobe)
            case .assistant: assistant
            }
        }
        .padding(6)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                lastMode = .reply
                model.run(.reply)
            } label: { Label("keyboard.reply", systemImage: "sparkles") }
            Button {
                lastMode = .polish
                model.run(.polish)
            } label: { Label("keyboard.polish", systemImage: "wand.and.stars") }
            Button {
                lastMode = .check
                model.run(.check)
            } label: { Label("keyboard.check", systemImage: "checkmark.shield") }
            Spacer()
            if model.panel == .assistant {
                Button("keyboard.back") { model.panel = .keys }
            }
        }
        .buttonStyle(.bordered)
        .font(.subheadline)
    }

    private var assistant: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ToneChip(title: "tone.humor", isOn: model.tone.humor) { model.toggleTone(\.humor) }
                ToneChip(title: "tone.warm", isOn: model.tone.warm) { model.toggleTone(\.warm) }
                ToneChip(title: "tone.direct", isOn: model.tone.direct) { model.toggleTone(\.direct) }
                ToneChip(title: "tone.brief", isOn: model.tone.brief) { model.toggleTone(\.brief) }
            }
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        if let check = model.check {
                            CheckBanner(check: check)
                        }
                        ForEach(model.suggestions) { suggestion in
                            Button {
                                model.use(suggestion, replacingDraft: lastMode != .reply)
                                model.clearImported()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.text).font(.body).foregroundStyle(.primary)
                                    Text(suggestion.why).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
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
        .padding(8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ToneChip: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color(uiColor: .systemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 字母键盘：中文模式下字母进入拼音缓冲区，候选栏显示在键盘上方
private struct LetterKeys: View {
    @ObservedObject var model: KeyboardModel
    let needsGlobe: Bool
    let onGlobe: () -> Void
    @State private var upper = false

    private let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    var body: some View {
        VStack(spacing: 6) {
            if model.chineseMode && !model.composing.isEmpty {
                CandidateBar(model: model)
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    if row == "zxcvbnm" {
                        if model.chineseMode {
                            key("'") { model.typeApostrophe() }
                        } else {
                            key(systemImage: upper ? "shift.fill" : "shift") { upper.toggle() }
                        }
                    }
                    ForEach(Array(row), id: \.self) { ch in
                        let letter = upper && !model.chineseMode ? String(ch).uppercased() : String(ch)
                        key(letter) { model.typeLetter(letter) }
                    }
                    if row == "zxcvbnm" {
                        key(systemImage: "delete.left") { model.tapDelete() }
                    }
                }
            }
            HStack(spacing: 4) {
                if needsGlobe { key(systemImage: "globe", action: onGlobe) }
                key(model.chineseMode ? "中" : "EN") { model.toggleLanguage() }
                key(model.chineseMode ? "，" : ",") { model.typePunctuation(model.chineseMode ? "，" : ",") }
                key(String(localized: "keyboard.space")) { model.tapSpace() }.frame(maxWidth: .infinity)
                key(model.chineseMode ? "。" : ".") { model.typePunctuation(model.chineseMode ? "。" : ".") }
                key(systemImage: "return") { model.tapReturn() }
            }
        }
    }

    private func key(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func key(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(minWidth: 40, minHeight: 40)
                .background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct CandidateBar: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.composing).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(model.candidates.enumerated()), id: \.offset) { _, candidate in
                        Button(candidate.text) { model.pick(candidate) }
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(height: 44)
    }
}
