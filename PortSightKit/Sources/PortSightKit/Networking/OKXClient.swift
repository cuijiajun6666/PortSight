//
//  OKXCurrency.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//


import Foundation
import CryptoKit
import Combine

public struct OKXCurrency: Decodable {
    public let ccy: String
    public let logoLink: String?

    public init(ccy: String, logoLink: String?) {
        self.ccy = ccy
        self.logoLink = logoLink
    }
}

public struct OKXAccountBalance: Decodable {
    public let totalEq: String?
    public let uTime: String?
    public let details: [OKXBalanceDetail]

    public init(totalEq: String?, uTime: String?, details: [OKXBalanceDetail]) {
        self.totalEq = totalEq
        self.uTime = uTime
        self.details = details
    }
}

public struct OKXBalanceDetail: Decodable {
    public let ccy: String

    public let spotBal: String?
    public let accAvgPx: String?

    public let spotUpl: String?
    public let spotUplRatio: String?

    public let totalPnl: String?
    public let totalPnlRatio: String?

    public let eqUsd: String?

    public init(ccy: String, spotBal: String?, accAvgPx: String?, spotUpl: String?, spotUplRatio: String?, totalPnl: String?, totalPnlRatio: String?, eqUsd: String?) {
        self.ccy = ccy
        self.spotBal = spotBal
        self.accAvgPx = accAvgPx
        self.spotUpl = spotUpl
        self.spotUplRatio = spotUplRatio
        self.totalPnl = totalPnl
        self.totalPnlRatio = totalPnlRatio
        self.eqUsd = eqUsd
    }
}

public final class OKXClient {
    public enum Env {
        case real
        case demo
    }

    private let apiKey: String
    private let secretKey: String
    private let passphrase: String
    private let env: Env

    private let baseURL: URL

    public init(apiKey: String, secretKey: String, passphrase: String, env: Env, baseURL: String = "https://app.okx.com") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.passphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        self.env = env
        self.baseURL = URL(string: baseURL)!
    }
    
    // 你要的：查看账户余额
    public func getAccountBalance() async throws -> OKXResponse<[OKXAccountBalance]> {
        let path = "/api/v5/account/balance"
        return try await request(
            method: "GET",
            path: path,
            queryItems: nil,
            body: nil,
            responseType: OKXResponse<[OKXAccountBalance]>.self
        )
    }

    // MARK: - Core request

    private func request<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?,
        body: Data?,
        responseType: T.Type
    ) async throws -> T {

        // 1) 拼 query
        var query = ""
        if let queryItems, !queryItems.isEmpty {
            var c = URLComponents()
            c.queryItems = queryItems
            query = c.percentEncodedQuery.map { "?\($0)" } ?? ""
        }

        // 2) requestPath 必须和最终 URL 路径一致（用于签名）
        let requestPath = path + query

        // 3) 最终 URL：用 baseURL.absoluteString + requestPath，避免 // 问题
        let url = URL(string: baseURL.absoluteString + requestPath)!
        var req = URLRequest(url: url)
        req.httpMethod = method.uppercased()
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let ts = iso8601Timestamp()
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        // 4) OKX prehash：timestamp + method + requestPath + body
        let prehash = ts + req.httpMethod! + requestPath + bodyString
        let sign = hmacSHA256Base64(message: prehash, secret: secretKey)

        req.setValue(apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
        req.setValue(sign, forHTTPHeaderField: "OK-ACCESS-SIGN")
        req.setValue(ts, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        req.setValue(passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")

        // ✅ 实盘就别加 x-simulated-trading
        // if env == .demo { req.setValue("1", forHTTPHeaderField: "x-simulated-trading") }

        // 5) 调试：先把这行打开，确认 URL 没有双斜杠
        //print("OKX URL:", url.absoluteString)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        if !(200..<300).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OKX_HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Helpers

    private func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private func hmacSHA256Base64(message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return Data(sig).base64EncodedString()
    }
}

extension OKXClient {
    public func getCurrencies(ccy: [String]? = nil) async throws -> OKXResponse<[OKXCurrency]> {
        let path = "/api/v5/asset/currencies"

        var items: [URLQueryItem] = []
        if let ccy, !ccy.isEmpty {
            // 支持多币种，用逗号分隔
            let value = ccy.map { $0.uppercased() }.joined(separator: ",")
            items.append(URLQueryItem(name: "ccy", value: value))
        }

        return try await request(
            method: "GET",
            path: path,
            queryItems: items.isEmpty ? nil : items,
            body: nil,
            responseType: OKXResponse<[OKXCurrency]>.self
        )
    }
}


//MARK: -- Currency Logo
@MainActor
public final class LogoStore: ObservableObject {
    @Published public private(set) var logoBySymbol: [String: URL] = [:]
    @Published public var errorText: String?

    private let client: OKXClient

    public init(client: OKXClient) { self.client = client }

    public func load(for symbols: [String]) async {
        do {
            let res = try await client.getCurrencies(ccy: symbols)
            guard res.code == "0" else {
                errorText = "OKX error \(res.code): \(res.msg)"
                return
            }

            var dict: [String: URL] = [:]
            for item in res.data {
                if let s = item.logoLink, let url = URL(string: s) {
                    dict[item.ccy.uppercased()] = url
                }
            }
            logoBySymbol.merge(dict) { _, new in new }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    public func logoURL(for symbol: String) -> URL? {
        logoBySymbol[symbol.uppercased()]
    }
}
