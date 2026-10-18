import PhotosUI
import SwiftUI

struct ImportView: View {
    @State private var item: PhotosPickerItem?
    @State private var turns: [ChatTurn] = SharedStore.shared.importedConversation
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker("import.pick", selection: $item, matching: .screenshots)
                    if isWorking { ProgressView() }
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section("import.review") {
                    ForEach($turns) { $turn in
                        HStack {
                            Picker("", selection: $turn.speaker) {
                                Text("speaker.them").tag(Speaker.them)
                                Text("speaker.me").tag(Speaker.me)
                            }
                            .labelsHidden()
                            .fixedSize()
                            TextField("", text: $turn.text, axis: .vertical)
                        }
                    }
                    .onDelete { turns.remove(atOffsets: $0) }
                }
                if !turns.isEmpty {
                    Button("import.save") { SharedStore.shared.importedConversation = turns }
                    Button("import.clear", role: .destructive) {
                        turns = []
                        SharedStore.shared.importedConversation = []
                    }
                }
            }
            .navigationTitle("import.title")
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task { await load(newItem) }
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            turns = try await ChatOCR.recognize(image)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
