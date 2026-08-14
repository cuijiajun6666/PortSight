//
//  OKXResponse.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//


import Foundation
import Combine

struct OKXResponse<T: Decodable>: Decodable {
    let code: String
    let msg: String
    let data: T
}

struct OKXIndexTicker: Decodable {
    let instId: String
    let idxPx: String
    let high24h: String?
    let low24h: String?
    let open24h: String?
    let sodUtc0: String?
    let sodUtc8: String?
    let ts: String
}

struct Asset: Identifiable {
    let id = UUID()

    let symbol: String      // "BTC"
    let instId: String      // "BTC-USDT"
    let quantity: Double    // 持仓数量
    let totalCost: Double   // 总成本（USDT）
    let avgCost: Double     // 平均成本（USDT）
}

final class OKXMarketService {
    private let baseURL = "https://www.okx.com"

    func fetchIndexTicker(instId: String) async throws -> OKXIndexTicker {
        var comps = URLComponents(string: baseURL + "/api/v5/market/index-tickers")!
        comps.queryItems = [
            URLQueryItem(name: "instId", value: instId)
        ]

        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(
            OKXResponse<[OKXIndexTicker]>.self,
            from: data
        )

        guard decoded.code == "0",
              let first = decoded.data.first else {
            throw NSError(
                domain: "OKX",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(decoded.code): \(decoded.msg)"]
            )
        }

        return first
    }
    
    // 拉 K 线，返回 [[String]]
        func fetchCandles(instId: String, bar: String, limit: Int = 90) async throws -> [[String]] {
            var comps = URLComponents(string: baseURL + "/api/v5/market/candles")!
            comps.queryItems = [
                URLQueryItem(name: "instId", value: instId),
                URLQueryItem(name: "bar", value: bar),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]

            guard let url = comps.url else { throw URLError(.badURL) }

            // ✅ 调试：打印 URL
            print("OKX Candles URL:", url.absoluteString)

            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            // ✅ 调试：打印 statusCode
            print("OKX Candles status:", http.statusCode)

            guard (200..<300).contains(http.statusCode) else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("OKX Candles error raw:", raw)
                throw NSError(domain: "OKX_HTTP", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: raw])
            }

            let decoded = try JSONDecoder().decode(OKXResponse<[[String]]>.self, from: data)
            guard decoded.code == "0" else {
                throw NSError(domain: "OKX", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "\(decoded.code): \(decoded.msg)"])
            }

            // ✅ 调试：打印前2条 / 后2条，确认顺序（是否最新在前）
            debugPrintCandles(decoded.data, instId: instId)

            return decoded.data
        }

        private func debugPrintCandles(_ candles: [[String]], instId: String) {
            print("---- Candles Debug \(instId) count=\(candles.count) ----")
            guard !candles.isEmpty else { return }

            let closesNewestFirst = self.extractCloses(from: candles, order: .newestFirst)
            let closesOldestFirst = self.extractCloses(from: candles, order: .oldestFirst)

            let cpNewest = closesNewestFirst.first ?? -1
            let cpOldest = closesOldestFirst.last ?? -1

            print("currentPrice(if newestFirst -> closes.first) =", cpNewest)
            print("currentPrice(if oldestFirst -> closes.last) =", cpOldest)
            print("-----------------------------------------")
        }
        enum CandleOrder {
            case newestFirst   // OKX 常见：data[0] 最新
            case oldestFirst
        }

        /// 提取 close 数组
        func extractCloses(from candles: [[String]], order: CandleOrder = .newestFirst) -> [Double] {
            let closes = candles.compactMap { row -> Double? in
                guard row.count > 4 else { return nil }
                return Double(row[4])
            }

            switch order {
            case .newestFirst:
                return closes // index 0 最新
            case .oldestFirst:
                return closes.reversed()
            }
        }
}




extension OKXMarketService {

    /// 从 OKX candles 中提取 close 价格
    /// OKX 返回是“最新在前”，我们反转成从旧到新
    func extractCloses(from candles: [[String]]) -> [Double] {

        // 反转顺序：旧 → 新（算收益率必须这样）
        let ordered = candles.reversed()

        var closes: [Double] = []
        closes.reserveCapacity(ordered.count)

        for row in ordered {
            // row[4] = close
            guard row.count > 4,
                  let close = Double(row[4]) else {
                continue
            }
            closes.append(close)
        }

        return closes
    }
}
