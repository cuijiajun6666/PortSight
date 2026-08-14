//
//  CompanyLogo.swift
//  PortSight
//
//  Created by Chris Cui on 17/5/2026.
//

import SwiftUI
import SwiftData
import Foundation

let LOGO_DEV_PUBLIC_KEY = "pk_SqIJPzG-Swq_mcIu-urXVA"

@Model
final class StockLogoRecord {
    @Attribute(.unique) var ticker: String
    var imageData: Data
    var updatedAt: Date
    var featureRed: Double?
    var featureGreen: Double?
    var featureBlue: Double?

    init(
        ticker: String,
        imageData: Data,
        updatedAt: Date = Date(),
        featureColor: LogoFeatureColor? = nil
    ) {
        self.ticker = ticker.uppercased()
        self.imageData = imageData
        self.updatedAt = updatedAt
        self.featureRed = featureColor?.red
        self.featureGreen = featureColor?.green
        self.featureBlue = featureColor?.blue
    }
}

extension StockLogoRecord {
    var featureColor: Color? {
        guard let red = featureRed,
              let green = featureGreen,
              let blue = featureBlue else {
            return nil
        }

        return Color(red: red, green: green, blue: blue)
    }
}

struct CompanyLogo: View {

    let ticker: String

    var body: some View {

        AsyncImage(
            url: URL(
                string: "https://img.logo.dev/ticker/\(ticker)?token=\(LOGO_DEV_PUBLIC_KEY)"
            )
        ) { image in

            image
                .resizable()
                .aspectRatio(contentMode: .fit)

        } placeholder: {

            ProgressView()
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// Direct download
func downloadCompanyLogo(ticker: String) async throws -> Data {

    let url = URL(
        string: "https://img.logo.dev/ticker/\(ticker)?token=\(LOGO_DEV_PUBLIC_KEY)"
    )!

    let (data, _) = try await URLSession.shared.data(from: url)

    return data
}

@MainActor
func syncStockLogoRecords(
    symbols: [String],
    records: [StockLogoRecord],
    modelContext: ModelContext
) async {
    let normalizedSymbols = Array(Set(symbols.map { $0.uppercased() })).sorted()
    guard !normalizedSymbols.isEmpty else { return }

    let cachedTickers = Set(records.map(\.ticker))
    let missingSymbols = normalizedSymbols.filter { !cachedTickers.contains($0) }
    let recordsMissingColor = records.filter {
        normalizedSymbols.contains($0.ticker) && $0.featureRed == nil
    }

    for symbol in missingSymbols {
        do {
            let data = try await downloadCompanyLogo(ticker: symbol)
            let record = StockLogoRecord(
                ticker: symbol,
                imageData: data,
                featureColor: extractLogoFeatureColor(from: data)
            )
            modelContext.insert(record)
        } catch {
            print("download company logo error:", symbol, error.localizedDescription)
        }
    }

    for record in recordsMissingColor {
        guard let featureColor = extractLogoFeatureColor(from: record.imageData) else { continue }
        record.featureRed = featureColor.red
        record.featureGreen = featureColor.green
        record.featureBlue = featureColor.blue
        record.updatedAt = Date()
    }

    guard !missingSymbols.isEmpty || !recordsMissingColor.isEmpty else { return }

    do {
        try modelContext.save()
    } catch {
        print("save company logos error:", error.localizedDescription)
    }
}
