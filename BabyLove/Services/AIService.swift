import Foundation

/// 调用后端代理 → Azure AI Foundry
/// 流程：StoreKit JWS → 后端换取 JWT → 用 JWT 调用 AI
actor AIService {
    static let shared = AIService()

    // ⚠️ 这里只放 Azure Function URL，不含任何 API Key
    private let workerBase = "https://babylove-ai-proxy.azurewebsites.net/api"

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast

    private init() {}

    // MARK: - Public

    /// 发送 prompt，返回 AI 回复
    func chat(prompt: String) async throws -> String {
        let token = try await validToken()
        return try await callChat(prompt: prompt, token: token)
    }

    // MARK: - Token 管理

    private func validToken() async throws -> String {
        // 缓存有效则直接用
        if let t = cachedToken, tokenExpiry > Date() { return t }

        // 检查购买状态（回到 MainActor 取 JWS）
        let jws = await MainActor.run { () -> Task<String?, Never> in
            Task { await PurchaseManager.shared.currentJWS() }
        }.value

        guard let jws else { throw AIError.notPurchased }

        let token = try await exchangeJWS(jws)
        cachedToken  = token
        tokenExpiry  = Date().addingTimeInterval(3600) // 缓存 1 小时
        return token
    }

    /// 用 Apple 签名的 JWS 换取我们自己的 JWT
    private func exchangeJWS(_ jws: String) async throws -> String {
        var req = URLRequest(url: try url("/auth"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody   = try JSONEncoder().encode(["jws": jws])
        req.timeoutInterval = 15

        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIError.authFailed((res as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }

    /// 用 JWT 调用 AI
    private func callChat(prompt: String, token: String) async throws -> String {
        var req = URLRequest(url: try url("/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody        = try JSONEncoder().encode(["prompt": prompt])
        req.timeoutInterval = 30

        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            // Token 过期 → 清缓存，让上层重试一次
            if (res as? HTTPURLResponse)?.statusCode == 401 {
                cachedToken = nil
                tokenExpiry = .distantPast
            }
            throw AIError.requestFailed((res as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data).content
    }

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: workerBase + path) else { throw AIError.badURL }
        return u
    }

    // MARK: - Errors

    enum AIError: LocalizedError {
        case notPurchased
        case authFailed(Int)
        case requestFailed(Int)
        case badURL

        var errorDescription: String? {
            switch self {
            case .notPurchased:        return "请先购买 AI Insights 功能"
            case .authFailed(let c):   return "购买验证失败 (\(c))"
            case .requestFailed(let c): return "AI 请求失败 (\(c))"
            case .badURL:              return "配置错误：Worker URL 无效"
            }
        }
    }
}

// MARK: - Response Models
private struct TokenResponse: Codable { let token: String }
private struct ChatResponse:  Codable { let content: String }
