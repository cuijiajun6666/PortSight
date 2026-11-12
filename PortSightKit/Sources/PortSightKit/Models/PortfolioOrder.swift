//
//  OrdersView.swift
//  PortSight
//
//  Created by Codex on 22/5/2026.
//

import Foundation

public struct PortfolioOrder: Identifiable {
    public enum Status {
        case pending
        case completed
    }

    public enum Side: String {
        case buy = "买入"
        case sell = "卖出"
    }

    public let id: String
    public let symbol: String
    public let side: Side
    public let status: Status
    public let price: Double
    public let quantity: Double
    public let date: Date
    public let orderStateText: String?
    /// "US.AAPL" → "AAPL"; a currency pair ("AUD.USD") stays whole.
    public var displaySymbol: String { SymbolLogoStore.displayTicker(symbol) }

    public init(
        id: String = UUID().uuidString,
        symbol: String,
        side: Side,
        status: Status,
        price: Double,
        quantity: Double,
        date: Date,
        orderStateText: String? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.side = side
        self.status = status
        self.price = price
        self.quantity = quantity
        self.date = date
        self.orderStateText = orderStateText
    }
}

public struct DealsResponse: Codable {
    public let ok: Bool
    public let updatedAt: String?
    public let count: Int?
    public let deals: [DealRecord]
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case updatedAt = "updated_at"
        case count
        case deals
        case error
    }

    public init(ok: Bool, updatedAt: String?, count: Int?, deals: [DealRecord], error: String?) {
        self.ok = ok
        self.updatedAt = updatedAt
        self.count = count
        self.deals = deals
        self.error = error
    }
}

public struct DealRecord: Codable, Identifiable {
    public var id: String { dealId }

    public let code: String
    public let stockName: String?
    public let dealId: String
    public let orderId: String?
    public let qty: Double
    public let price: Double
    public let trdSide: String
    public let createTime: String
    public let status: String?

    public enum CodingKeys: String, CodingKey {
        case code
        case stockName = "stock_name"
        case dealId = "deal_id"
        case orderId = "order_id"
        case qty
        case price
        case trdSide = "trd_side"
        case createTime = "create_time"
        case status
    }

    public var asPortfolioOrder: PortfolioOrder {
        PortfolioOrder(
            id: dealId,
            symbol: code,
            side: trdSide.uppercased() == "SELL" ? .sell : .buy,
            status: .completed,
            price: price,
            quantity: qty,
            date: Self.parseDate(createTime) ?? .distantPast,
            orderStateText: status
        )
    }

    public static func parseDate(_ value: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        let isoNoFractionFormatter = ISO8601DateFormatter()
        isoNoFractionFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoNoFractionFormatter.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")

        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    public init(code: String, stockName: String?, dealId: String, orderId: String?, qty: Double, price: Double, trdSide: String, createTime: String, status: String?) {
        self.code = code
        self.stockName = stockName
        self.dealId = dealId
        self.orderId = orderId
        self.qty = qty
        self.price = price
        self.trdSide = trdSide
        self.createTime = createTime
        self.status = status
    }
}

public struct OpenOrdersResponse: Codable {
    public let ok: Bool
    public let cached: Bool?
    public let cacheAgeSeconds: Double?
    public let updatedAt: String?
    public let source: String?
    public let count: Int?
    public let orders: [OpenOrderRecord]
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case ok
        case cached
        case cacheAgeSeconds = "cache_age_seconds"
        case updatedAt = "updated_at"
        case source
        case count
        case orders
        case error
    }

    public init(ok: Bool, cached: Bool?, cacheAgeSeconds: Double?, updatedAt: String?, source: String?, count: Int?, orders: [OpenOrderRecord], error: String?) {
        self.ok = ok
        self.cached = cached
        self.cacheAgeSeconds = cacheAgeSeconds
        self.updatedAt = updatedAt
        self.source = source
        self.count = count
        self.orders = orders
        self.error = error
    }
}

public struct OpenOrderRecord: Codable, Identifiable {
    public var id: String { orderId }

    public let code: String
    public let stockName: String?
    public let orderMarket: String?
    public let trdSide: String
    public let orderType: String?
    public let orderStatus: String
    public let orderId: String
    public let qty: Double
    public let price: Double
    public let createTime: String
    public let updatedTime: String?
    public let dealtQty: Double?
    public let dealtAvgPrice: Double?
    public let lastErrMsg: String?
    public let remark: String?
    public let timeInForce: String?
    public let fillOutsideRth: Bool?
    public let session: String?
    public let currency: String?

    public enum CodingKeys: String, CodingKey {
        case code
        case stockName = "stock_name"
        case orderMarket = "order_market"
        case trdSide = "trd_side"
        case orderType = "order_type"
        case orderStatus = "order_status"
        case orderId = "order_id"
        case qty
        case price
        case createTime = "create_time"
        case updatedTime = "updated_time"
        case dealtQty = "dealt_qty"
        case dealtAvgPrice = "dealt_avg_price"
        case lastErrMsg = "last_err_msg"
        case remark
        case timeInForce = "time_in_force"
        case fillOutsideRth = "fill_outside_rth"
        case session
        case currency
    }

    public var asPortfolioOrder: PortfolioOrder {
        PortfolioOrder(
            id: orderId,
            symbol: code,
            side: trdSide.uppercased() == "SELL" ? .sell : .buy,
            status: .pending,
            price: price,
            quantity: qty,
            date: DealRecord.parseDate(createTime) ?? .distantPast,
            orderStateText: orderStatus
        )
    }

    public init(code: String, stockName: String?, orderMarket: String?, trdSide: String, orderType: String?, orderStatus: String, orderId: String, qty: Double, price: Double, createTime: String, updatedTime: String?, dealtQty: Double?, dealtAvgPrice: Double?, lastErrMsg: String?, remark: String?, timeInForce: String?, fillOutsideRth: Bool?, session: String?, currency: String?) {
        self.code = code
        self.stockName = stockName
        self.orderMarket = orderMarket
        self.trdSide = trdSide
        self.orderType = orderType
        self.orderStatus = orderStatus
        self.orderId = orderId
        self.qty = qty
        self.price = price
        self.createTime = createTime
        self.updatedTime = updatedTime
        self.dealtQty = dealtQty
        self.dealtAvgPrice = dealtAvgPrice
        self.lastErrMsg = lastErrMsg
        self.remark = remark
        self.timeInForce = timeInForce
        self.fillOutsideRth = fillOutsideRth
        self.session = session
        self.currency = currency
    }
}

