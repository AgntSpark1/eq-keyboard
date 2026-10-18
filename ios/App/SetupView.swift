import SwiftUI

struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("setup.steps") {
                    Text("setup.step1")
                    Text("setup.step2")
                    Text("setup.step3")
                }
                Section {
                    Text("setup.privacy").font(.footnote).foregroundStyle(.secondary)
                }
                Button("setup.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .navigationTitle("setup.title")
        }
    }
}
