//
//  OKXCredentials.swift
//  PortSight
//
//  OKX API key, secret and passphrase in this device's Keychain (they used to be written into DashboardView).
//  Entered once in Settings → OKX 只读密钥; never shown again, never logged. Use a read-only key without
//  withdrawal or trading permission.
//

import Foundation

public struct OKXCredentials {
    public static let service = "PortSight.okx"
    public var apiKey: String
    public var secretKey: String
    public var passphrase: String

    public init(apiKey: String, secretKey: String, passphrase: String) {
        self.apiKey = apiKey; self.secretKey = secretKey; self.passphrase = passphrase
    }

    public static func load() -> OKXCredentials? {
        guard let k = ServerKeychain.read(service: service, account: "api_key"),
              let s = ServerKeychain.read(service: service, account: "secret_key"),
              let p = ServerKeychain.read(service: service, account: "passphrase"),
              !k.isEmpty, !s.isEmpty, !p.isEmpty else { return nil }
        return OKXCredentials(apiKey: k, secretKey: s, passphrase: p)
    }

    public func save() -> Bool {
        ServerKeychain.save(apiKey, service: Self.service, account: "api_key")
            && ServerKeychain.save(secretKey, service: Self.service, account: "secret_key")
            && ServerKeychain.save(passphrase, service: Self.service, account: "passphrase")
    }

    public static func clear() {
        for account in ["api_key", "secret_key", "passphrase"] { ServerKeychain.delete(service: service, account: account) }
    }
}
