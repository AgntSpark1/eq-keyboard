import SwiftUI

struct ProfileView: View {
    @State private var profile = SharedStore.shared.profile ?? PartnerProfile()
    @State private var interests = (SharedStore.shared.profile?.interests ?? []).joined(separator: ", ")

    var body: some View {
        NavigationStack {
            Form {
                TextField("profile.name", text: $profile.name)
                Picker("profile.stage", selection: $profile.stage) {
                    Text("stage.just_met").tag(RelationshipStage.justMet)
                    Text("stage.flirting").tag(RelationshipStage.flirting)
                    Text("stage.dating").tag(RelationshipStage.dating)
                    Text("stage.relationship").tag(RelationshipStage.relationship)
                }
                TextField("profile.interests", text: $interests)
                TextField("profile.notes", text: $profile.notes, axis: .vertical)
                Section {
                    Text("profile.localOnly").font(.footnote).foregroundStyle(.secondary)
                }
                Button("profile.save") {
                    profile.interests = interests
                        .split(whereSeparator: { $0 == "," || $0 == "，" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    SharedStore.shared.profile = profile
                }
            }
            .navigationTitle("profile.title")
        }
    }
}
