import StoreKit
import Foundation

/// 管理 AI Insights 功能的一次性购买（StoreKit 2）
@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    // App Store Connect 里配置的产品 ID
    static let aiProductID = "com.babylove.xym.app.ai_insights"

    var isPurchased = false
    var isLoading   = false
    var errorMessage: String?

    private var listenerTask: Task<Void, Never>?

    private init() {
        listenerTask = Task { await listenForTransactions() }
        Task { await refreshStatus() }
    }

    deinit {
        let task = MainActor.assumeIsolated { listenerTask }
        task?.cancel()
    }

    // MARK: - Public

    func purchase() async {
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: [Self.aiProductID])
            guard let product = products.first else {
                errorMessage = "Product not found — check App Store Connect"
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let tx = try unwrap(verification)
                await tx.finish()
                isPurchased = true
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshStatus()
    }

    /// 返回 Apple 签名的 JWS Transaction（发给后端验证用）
    func currentJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            if case let .verified(tx) = result, tx.productID == Self.aiProductID {
                return result.jwsRepresentation
            }
        }
        return nil
    }

    // MARK: - Private

    func refreshStatus() async {
        for await result in Transaction.currentEntitlements {
            if case let .verified(tx) = result, tx.productID == Self.aiProductID {
                isPurchased = true
                return
            }
        }
        isPurchased = false
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case let .verified(tx) = result, tx.productID == Self.aiProductID {
                await tx.finish()
                isPurchased = true
            }
        }
    }

    private func unwrap<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let err): throw err
        case .verified(let value):    return value
        }
    }
}
