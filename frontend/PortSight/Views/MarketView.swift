//
//  MarketIndex.swift
//  PortSight
//
//  Created by Chris Cui on 2/5/2026.
//


import SwiftUI

struct MarketIndex: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    
    var color: Color {
        change >= 0 ? .green : .red
    }
}

let mockMarketIndexes: [MarketIndex] = [
    MarketIndex(name: "S&P 500", symbol: "SPX", price: 5123.41, change: 32.18, changePercent: 0.63),
    MarketIndex(name: "NASDAQ", symbol: "IXIC", price: 16340.87, change: -84.22, changePercent: -0.51),
    MarketIndex(name: "Dow Jones", symbol: "DJI", price: 38920.10, change: 120.55, changePercent: 0.31),
    MarketIndex(name: "ASX 200", symbol: "XJO", price: 7820.45, change: -15.32, changePercent: -0.20)
]

struct MarketView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(mockMarketIndexes) { index in
                        MarketIndexRow(index: index)
                    }
                } header: {
                    Text("大盘指数")
                }
                
                Section {
                    PlaceholderMarketChart()
                } header: {
                    Text("市场走势")
                }
                
                Section {
                    MarketPlaceholderCard(title: "市场情绪", value: "Neutral", subtitle: "Placeholder")
                    MarketPlaceholderCard(title: "热门板块", value: "Technology", subtitle: "Placeholder")
                    MarketPlaceholderCard(title: "成交活跃", value: "TSLA / NVDA / AAPL", subtitle: "Placeholder")
                } header: {
                    Text("市场概览")
                }
                
                Section {
                    Text("恐慌指数VIX分析，可以放在tabViewBottomAccessory点进去")
                }
            }
            .navigationTitle("Market")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MarketIndexRow: View {
    let index: MarketIndex
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(index.name)
                    .font(.headline)
                
                Text(index.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(index.price, specifier: "%.2f")")
                    .font(.headline)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: index.price)
                
                HStack(spacing: 4) {
                    Text("\(index.change >= 0 ? "+" : "")\(index.change, specifier: "%.2f")")
                    Text("(\(index.changePercent >= 0 ? "+" : "")\(index.changePercent, specifier: "%.2f")%)")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(index.color)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlaceholderMarketChart: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .frame(height: 180)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    
                    Text("Market Chart Placeholder")
                        .font(.headline)
                    
                    Text("后面这里接指数 K 线 / 大盘走势图")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

struct MarketPlaceholderCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
