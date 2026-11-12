//
//  LiveTradeCard.swift
//  PortsightMac
//
//  The trade selected on the 实时 chart (an open position or a closed trade): its result, the figures two to a
//  row, how its size and stop changed, and in a column on the right its 交易理由 (TradeReasonPanel). It is as tall
//  as the chart (beside it, or under it in narrow windows) and each column scrolls on its own.
//

import SwiftUI
import PortSightKit

struct LiveTradeCard: View {
    let model: LiveViewerModel
    let position: LivePosition?
    let record: LiveTradeRecord?
    /// The chart's height; the columns scroll inside it.
    let height: CGFloat
    let close: () -> Void

    static let reasonWidth: CGFloat = 270

    private var feed: LiveFeed { model.feed }
    private var currency: String { model.account?.currency ?? "USDT" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 16) {
                column { details }
                    .frame(minWidth: 250, maxWidth: .infinity, alignment: .topLeading)
                Divider()
                column { reasons }
                    .frame(width: Self.reasonWidth, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).monospaced()
            }
            Spacer()
            Button(action: close) { Image(systemName: "xmark") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .accessibilityLabel("关闭详情")
        }
    }

    private var title: String {
        if let position { return position.contractTitle + " · " + position.side.title }
        if let record { return LiveFormat.contractTitle(record.trade.symbol) + " · " + record.trade.side.title }
        return "交易"
    }

    private var subtitle: String {
        if let position { return position.tradeId + " · 持仓中" }
        if let record { return record.trade.id + " · 已平仓 · " + record.trade.exitTitle }
        return ""
    }

    // MARK: Left column

    @ViewBuilder
    private var details: some View {
        if let position {
            positionDetails(position)
        } else if let record {
            recordDetails(record)
        }
    }

    private func positionDetails(_ position: LivePosition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LiveFormat.signedMoney(position.unrealizedPnl))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesktopTheme.pnlColor(position.unrealizedPnl))
                    .contentTransition(.numericText(value: position.unrealizedPnl))
                    .animation(.smooth(duration: 0.3), value: position.unrealizedPnl)
                Text("未实现盈亏（\(currency)）· 按保证金 " + BacktestFormat.percent(position.unrealizedPct))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Divider()
            fieldGrid([
                Field("数量", LiveFormat.size(position.size) + " 张 · " + String(format: "%.0f×", position.leverage)),
                Field("开仓均价", LiveFormat.price(position.entryPx)),
                Field("标记价", LiveFormat.price(position.markPx)),
                Field("强平价", position.liquidationPx.map(LiveFormat.price) ?? "—"),
                Field("止损", position.stopPx.map(LiveFormat.price) ?? "—"),
                Field("止盈", position.targetPx.map(LiveFormat.price) ?? "—"),
                Field("保证金", LiveFormat.money(position.margin)),
                Field("已实现", LiveFormat.signedMoney(position.realizedPnl), tint: DesktopTheme.pnlColor(position.realizedPnl)),
                Field("手续费", LiveFormat.money(position.fee)),
                Field("持有", BacktestFormat.hours((feed.now - position.openedAt) / 3_600_000)),
                Field("开仓", LiveFormat.time(position.openedAt)),
                Field("模型", position.model),
            ])
            changes(steps: position.sizePath.map { (title: $0.title, step: $0) }, stops: position.stops)
        }
    }

    private func recordDetails(_ record: LiveTradeRecord) -> some View {
        let trade = record.trade
        let net = record.realizedPnl - record.fee
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LiveFormat.signedMoney(net))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(DesktopTheme.pnlColor(net))
                Text("净盈亏（\(currency)）· 占权益 " + BacktestFormat.percent(trade.pnlNet, digits: 3))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Divider()
            fieldGrid([
                Field("开仓价", LiveFormat.price(trade.entryPx)),
                Field("平仓价", LiveFormat.price(trade.exitPx)),
                Field("开仓", LiveFormat.time(trade.entryT)),
                Field("平仓", LiveFormat.time(trade.exitT)),
                Field("持有", BacktestFormat.hours(trade.holdH)),
                Field("价格变动", BacktestFormat.percent(trade.priceReturn)),
                Field("已实现", LiveFormat.signedMoney(record.realizedPnl), tint: DesktopTheme.pnlColor(record.realizedPnl)),
                Field("手续费", LiveFormat.money(record.fee)),
                Field("最大浮盈", BacktestFormat.percent(trade.mfe, digits: 3)),
                Field("最大浮亏", BacktestFormat.percent(trade.mae, digits: 3)),
                Field("平仓原因", trade.exitTitle),
                Field("模型", record.model),
            ])
            if !trade.signalsAtEntry.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开仓时信号").font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(trade.signalsAtEntry.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).monospaced().lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(String(format: "%.4f", trade.signalsAtEntry[key] ?? 0)).monospacedDigit()
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            changes(steps: trade.sizePath.map { (title: trade.title(of: $0), step: $0) }, stops: trade.stops)
        }
    }

    // MARK: Figures

    private struct Field {
        let label: String
        let value: String
        var tint: Color = .primary

        init(_ label: String, _ value: String, tint: Color = .primary) {
            self.label = label
            self.value = value
            self.tint = tint
        }
    }

    /// Two figures to a row, each a small label over its value.
    private func fieldGrid(_ fields: [Field]) -> some View {
        let rows = stride(from: 0, to: fields.count, by: 2).map { Array(fields[$0..<min($0 + 2, fields.count)]) }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, field in fieldCell(field) }
                    if row.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
    }

    private func fieldCell(_ field: Field) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(field.label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(field.value).font(.system(size: 12.5)).monospacedDigit()
                .foregroundStyle(field.tint)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Size steps and stop moves, when there was more than the opening one.
    @ViewBuilder
    private func changes(steps: [(title: String, step: BacktestSizeStep)], stops: [BacktestLevel]) -> some View {
        if steps.count > 1 || stops.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text("仓位与止损变化").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.title)
                        Spacer()
                        Text(BacktestFormat.plainPercent(abs(item.step.w)) + " · " + LiveFormat.time(item.step.t))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(stops.dropFirst().enumerated()), id: \.offset) { _, level in
                    HStack {
                        Text("止损移到 " + LiveFormat.price(level.px))
                        Spacer()
                        Text(LiveFormat.time(level.t)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 11)).monospacedDigit()
        }
    }

    // MARK: Right column

    @ViewBuilder
    private var reasons: some View {
        if let position {
            TradeReasonPanel(symbol: position.contract, side: position.side, tradeID: position.tradeId, start: position.openedAt, end: feed.now)
        } else if let record {
            TradeReasonPanel(symbol: record.trade.symbol, side: record.trade.side, tradeID: record.trade.id, start: record.trade.entryT,
                             end: record.trade.exitT)
        }
    }
}
