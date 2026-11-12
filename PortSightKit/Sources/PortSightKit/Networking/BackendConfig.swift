//
//  BackendConfig.swift
//  PortSight
//
//  Created by Codex on 21/5/2026.
//

import Foundation

public enum BackendConfig {
    public static let storageKey = "backend_base_url"

    /// No built-in address: the old public plain-HTTP server is no longer used. Set the Mac mini's Tailscale HTTPS
    /// address (https://<name>.<tailnet>.ts.net[:port]) in Settings; until then nothing is requested.
    public static let defaultBaseURL = ""

    public static var baseURLString: String {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? ""
        let normalized = normalize(saved)
        return normalized.isEmpty ? defaultBaseURL : normalized
    }

    public static func normalize(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if !value.localizedCaseInsensitiveContains("://") {
            value = "https://\(value)"
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        return value
    }

    public static func save(_ rawValue: String) {
        let normalized = normalize(rawValue)
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            UserDefaults.standard.set(normalized, forKey: storageKey)
        }
    }

    public static func url(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        if DemoPortfolioData.enabled { return nil }
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        // HTTPS only (Tailscale): a plain-http address is ignored rather than sent over the internet in clear text.
        guard var components = URLComponents(string: baseURLString), components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else { return nil }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = [basePath, cleanPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/\(fullPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}
