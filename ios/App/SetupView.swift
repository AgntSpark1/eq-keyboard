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
                    Text("setup.wechat1")
                    Text("setup.wechat2")
                } header: {
                    Text("setup.wechat")
                }
                Section {
                    Text("setup.backTap1")
                    Text("setup.backTap2")
                    Text("setup.backTap3")
                } header: {
                    Text("setup.backTap")
                } footer: {
                    Text("setup.backTapNote")
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
