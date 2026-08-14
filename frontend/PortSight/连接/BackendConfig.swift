//
//  BackendConfig.swift
//  PortSight
//
//  Created by Codex on 21/5/2026.
//

import Foundation

enum BackendConfig {
    static let storageKey = "backend_base_url"

    static let defaultBaseURL = "http://45.63.31.248:8000"

    static var baseURLString: String {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? ""
        let normalized = normalize(saved)
        return normalized.isEmpty ? defaultBaseURL : normalized
    }

    static func normalize(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }

        if !value.localizedCaseInsensitiveContains("://") {
            value = "http://\(value)"
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        return value
    }

    static func save(_ rawValue: String) {
        let normalized = normalize(rawValue)
        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else {
            UserDefaults.standard.set(normalized, forKey: storageKey)
        }
    }

    static func url(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(string: baseURLString) else { return nil }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = [basePath, cleanPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        components.path = "/\(fullPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}
