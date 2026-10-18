import AuthenticationServices
import Foundation
import StoreKit

/// 账号与订阅：Sign in with Apple 换后端会话，StoreKit 2 购买后交给后端校验。
@MainActor
final class AccountModel: ObservableObject {
    /// 与 App Store Connect 里创建的订阅商品 ID 保持一致
    static let productIds = ["eqkeyboard.pro.monthly", "eqkeyboard.pro.yearly"]

    @Published var isSignedIn: Bool
    @Published var status: AccountStatus?
    @Published var products: [Product] = []
    @Published var isWorking = false
    @Published var message: String?

    private let api = APIClient()
    private let store = SharedStore.shared
    private var updates: Task<Void, Never>?

    init() {
        isSignedIn = SharedStore.shared.sessionToken != nil
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    deinit { updates?.cancel() }

    func load() async {
        if products.isEmpty {
            products = (try? await Product.products(for: Self.productIds))?.sorted { $0.price < $1.price } ?? []
        }
        guard isSignedIn else { return }
        do {
            status = try await api.account()
        } catch APIError.server(401) {
            signOut()
        } catch {
            message = error.localizedDescription
        }
    }

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = []
    }

    func completeSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code == .canceled { return }
            message = String(localized: "account.signInFailed")
            return
        }
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                let session = try await api.signInWithApple(identityToken: token)
                store.sessionToken = session.sessionToken
                store.userId = session.userId
                isSignedIn = true
                await load()
            } catch {
                message = String(localized: "account.signInFailed")
            }
        }
    }

    func signOut() {
        store.sessionToken = nil
        store.userId = nil
        isSignedIn = false
        status = nil
    }

    func purchase(_ product: Product) async {
        guard let userId = store.userId, let token = UUID(uuidString: userId) else {
            message = String(localized: "account.signInFirst")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case .success(let result): await handle(result)
            case .pending: message = String(localized: "account.pending")
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// 恢复购买：重新把当前有效的订阅交给后端
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            await handle(result)
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        if isSignedIn {
            do {
                status = try await api.verifySubscription(signedTransaction: result.jwsRepresentation)
            } catch {
                message = error.localizedDescription
                return
            }
        }
        await transaction.finish()
    }
}
