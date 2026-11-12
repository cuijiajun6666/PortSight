//
//  CacheManager.swift
//  PortSight
//
//  Created by Chris Cui on 1/5/2026.
//


import Foundation

public enum CacheManager {
    
    public static func save<T: Codable>(_ value: T, key: String) {
        if DemoPortfolioData.enabled { return }
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Cache save error:", error)
        }
    }
    
    public static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        if DemoPortfolioData.enabled { return nil }
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("Cache load error:", error)
            return nil
        }
    }

    public static func loadAsync<T: Codable>(_ type: T.Type, key: String) async -> T? {
        if DemoPortfolioData.enabled { return nil }
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        do {
            return try await decode(type, from: data)
        } catch {
            print("Cache load error:", error)
            return nil
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .utility) {
            try JSONDecoder().decode(type, from: data)
        }.value
    }

    public static func saveAsync<T: Codable>(_ value: T, key: String) async {
        if DemoPortfolioData.enabled { return }
        await Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(value)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                print("Cache save error:", error)
            }
        }.value
    }
}
