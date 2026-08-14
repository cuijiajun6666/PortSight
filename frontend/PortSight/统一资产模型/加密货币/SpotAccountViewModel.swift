//
//  SpotAccountViewModel.swift
//  PortSight
//
//  Created by Chris Cui on 4/5/2026.
//

import Combine
import Foundation

@MainActor
final class SpotAccountViewModel: ObservableObject {
    @Published var totalEqUSD: Double = 0
    @Published var details: [OKXBalanceDetail] = []
    @Published var errorText: String?
    @Published var lastUpdated: Date?

    private let client: OKXClient
    private var task: Task<Void, Never>?

    var spotHoldings: [OKXBalanceDetail] {
        details
            .filter { $0.quantity > 0 && $0.marketValue > 0 }
            .sorted { $0.marketValue > $1.marketValue }
    }

    init(client: OKXClient) {
        self.client = client
    }

    func refresh() async {
        do {
            let res = try await client.getAccountBalance()

            guard res.code == "0",
                  let first = res.data.first else {
                errorText = "OKX error \(res.code): \(res.msg)"
                return
            }

            totalEqUSD = Double(first.totalEq ?? "") ?? 0
            details = first.details
            lastUpdated = Date()
            errorText = nil

        } catch {
            errorText = error.localizedDescription
            print("OKX price error:", error.localizedDescription)
        }
    }

    func startPolling(every seconds: Double = 3.0) {
        task?.cancel()

        task = Task {
            while !Task.isCancelled {
                await refresh()

                try? await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
            }
        }
    }

    func stopPolling() {
        task?.cancel()
        task = nil
    }
}
