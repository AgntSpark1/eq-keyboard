import AuthenticationServices
import StoreKit
import SwiftUI

struct AccountView: View {
    @StateObject private var model = AccountModel()

    var body: some View {
        NavigationStack {
            List {
                if model.isSignedIn {
                    statusSection
                    if model.status?.subscribed != true { plansSection }
                    Section {
                        Button("account.restore") { Task { await model.restore() } }
                        Button("account.signOut", role: .destructive) { model.signOut() }
                    }
                } else {
                    Section {
                        Text("account.why").font(.footnote).foregroundStyle(.secondary)
                        SignInWithAppleButton(.signIn, onRequest: model.configure, onCompletion: model.completeSignIn)
                            .frame(height: 48)
                    }
                }
                if let message = model.message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .disabled(model.isWorking)
            .overlay { if model.isWorking { ProgressView() } }
            .navigationTitle("account.title")
            .task { await model.load() }
        }
    }

    private var statusSection: some View {
        Section {
            if model.status?.subscribed == true {
                Label("account.subscribed", systemImage: "checkmark.seal.fill")
                if let expires = model.status?.subscriptionExpiresAt {
                    Text(Date(timeIntervalSince1970: expires / 1000), format: .dateTime.year().month().day())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("account.free")
            }
            if let remaining = model.status?.quotaRemaining {
                Text(String(format: String(localized: "account.remaining"), remaining))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plansSection: some View {
        Section("account.plans") {
            ForEach(model.products) { product in
                Button {
                    Task { await model.purchase(product) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.displayName)
                            Text(product.description).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice).bold()
                    }
                }
            }
            if model.products.isEmpty {
                Text("account.noProducts").font(.footnote).foregroundStyle(.secondary)
            }
            Text("account.terms").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
