//
//  VaultPasscode.swift
//  PortSight
//
//  The vault's own 6-digit passcode (separate from the device passcode). Only a salted SHA-256 hash is kept,
//  in this device's Keychain. Five wrong tries lock entry for 30 seconds.
//

import Foundation
import CryptoKit

public enum VaultPasscode {
    public static let length = 6
    public static let maxAttempts = 5
    public static let lockout: TimeInterval = 30

    private static let service = "PortSight.vault"
    private static let hashAccount = "passcode.hash"
    private static let saltAccount = "passcode.salt"

    public static var isSet: Bool { ServerKeychain.read(service: service, account: hashAccount) != nil }

    public static func isValidFormat(_ code: String) -> Bool {
        code.count == length && code.allSatisfy(\.isNumber)
    }

    @discardableResult
    public static func set(_ code: String) -> Bool {
        guard isValidFormat(code) else { return false }
        let salt = UUID().uuidString
        return ServerKeychain.save(salt, service: service, account: saltAccount)
            && ServerKeychain.save(hash(code, salt: salt), service: service, account: hashAccount)
    }

    public static func verify(_ code: String) -> Bool {
        guard let salt = ServerKeychain.read(service: service, account: saltAccount),
              let stored = ServerKeychain.read(service: service, account: hashAccount) else { return false }
        return hash(code, salt: salt) == stored
    }

    public static func clear() {
        ServerKeychain.delete(service: service, account: hashAccount)
        ServerKeychain.delete(service: service, account: saltAccount)
    }

    private static func hash(_ code: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + ":" + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
