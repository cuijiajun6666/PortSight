//
//  CacheManager.swift
//  PortSight
//
//  Created by Chris Cui on 1/5/2026.
//


import Foundation

enum CacheManager {
    
    static func save<T: Codable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Cache save error:", error)
        }
    }
    
    static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
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

    static func loadAsync<T: Codable>(_ type: T.Type, key: String) async -> T? {
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

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try await Task.detached(priority: .utility) {
            try JSONDecoder().decode(type, from: data)
        }.value
    }

    static func saveAsync<T: Codable>(_ value: T, key: String) async {
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
