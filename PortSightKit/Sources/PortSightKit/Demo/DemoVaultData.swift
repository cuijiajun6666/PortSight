//
//  DemoVaultData.swift
//  PortSight
//
//  Fictional documents for the family file vault (文件保险箱): ID papers, insurance, property and medical
//  records, with the fields a local OCR / vision model would read out. Numbers are fake and shown masked.
//  The real vault is meant to live on the family's home machine in China, reached over the private network.
//

import Foundation

public struct VaultDocument: Identifiable, Hashable {
    public enum Category: String, CaseIterable, Identifiable {
        case identity = "证件", insurance = "保险", property = "房产", medical = "医疗"
        public var id: String { rawValue }
        public var icon: String {
            switch self {
            case .identity: "person.text.rectangle"
            case .insurance: "cross.case"
            case .property: "house"
            case .medical: "heart.text.square"
            }
        }
    }

    public struct Field: Hashable {
        public let label: String
        public let value: String
        /// Shown as dots until the viewer taps to reveal it.
        public let sensitive: Bool
    }

    public let id: String
    public let title: String
    public let ownerID: String
    public let category: Category
    public let expires: Date?
    public let fields: [Field]
    public let pages: Int
    public let addedAt: Date

    /// Days until expiry (negative when already expired); nil for documents that do not expire.
    public func daysToExpiry(from now: Date = .now) -> Int? {
        expires.map { Calendar.current.dateComponents([.day], from: now, to: $0).day ?? 0 }
    }
}

public struct VaultAnswer: Hashable {
    public let answer: String
    public let documentIDs: [String]
}

public enum DemoVaultData {
    private static let calendar = Calendar(identifier: .gregorian)
    private static func inDays(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: .now) ?? .now }
    private static func ago(_ days: Int) -> Date { inDays(-days) }

    public static let documents: [VaultDocument] = [
        VaultDocument(id: "passport-dad", title: "护照", ownerID: "dad", category: .identity, expires: inDays(74),
                      fields: [.init(label: "姓名", value: "爸爸", sensitive: false),
                               .init(label: "护照号", value: "E12345678", sensitive: true),
                               .init(label: "签发地", value: "上海", sensitive: false)],
                      pages: 2, addedAt: ago(320)),
        VaultDocument(id: "id-mom", title: "身份证", ownerID: "mom", category: .identity, expires: inDays(1_460),
                      fields: [.init(label: "姓名", value: "妈妈", sensitive: false),
                               .init(label: "证件号", value: "310101196801010000", sensitive: true),
                               .init(label: "住址", value: "上海市黄浦区", sensitive: true)],
                      pages: 2, addedAt: ago(500)),
        VaultDocument(id: "passport-me", title: "护照", ownerID: "me", category: .identity, expires: inDays(2_100),
                      fields: [.init(label: "护照号", value: "EA7654321", sensitive: true),
                               .init(label: "签发地", value: "悉尼领馆", sensitive: false)],
                      pages: 2, addedAt: ago(150)),
        VaultDocument(id: "insurance-grandpa", title: "医疗保险", ownerID: "grandpa", category: .insurance, expires: inDays(21),
                      fields: [.init(label: "保单号", value: "PICC-2025-000123", sensitive: true),
                               .init(label: "保障期", value: "一年，到期需续保", sensitive: false),
                               .init(label: "联系电话", value: "95518", sensitive: false)],
                      pages: 6, addedAt: ago(340)),
        VaultDocument(id: "insurance-car", title: "车险", ownerID: "dad", category: .insurance, expires: inDays(190),
                      fields: [.init(label: "保单号", value: "CPIC-2026-004567", sensitive: true),
                               .init(label: "车牌", value: "沪A·12345", sensitive: true)],
                      pages: 3, addedAt: ago(170)),
        VaultDocument(id: "property", title: "房产证", ownerID: "mom", category: .property, expires: nil,
                      fields: [.init(label: "坐落", value: "上海市黄浦区", sensitive: true),
                               .init(label: "面积", value: "89.5 平方米", sensitive: false)],
                      pages: 4, addedAt: ago(900)),
        VaultDocument(id: "checkup-grandma", title: "体检报告 2026", ownerID: "grandma", category: .medical, expires: nil,
                      fields: [.init(label: "医院", value: "社区医院", sensitive: false),
                               .init(label: "结论", value: "血压略高，建议三个月后复查", sensitive: false)],
                      pages: 12, addedAt: ago(40)),
    ]

    public static let questions = ["爸爸的护照什么时候到期？", "外公的保险要续了吗？", "外婆上次体检怎么说？"]

    public static func document(_ id: String) -> VaultDocument? { documents.first { $0.id == id } }

    /// Documents expiring within 90 days, soonest first.
    public static var expiringSoon: [VaultDocument] {
        documents.filter { ($0.daysToExpiry() ?? .max) <= 90 }.sorted { ($0.daysToExpiry() ?? 0) < ($1.daysToExpiry() ?? 0) }
    }

    /// Demo of asking the vault in plain language (OCR fields + dates, answered by the local model).
    public static func answer(_ question: String) -> VaultAnswer? {
        if question.contains("护照") && (question.contains("爸") || question.contains("父")) {
            let doc = documents[0]
            return VaultAnswer(answer: "爸爸的护照 \(doc.expires.map { $0.formatted(date: .long, time: .omitted) } ?? "")到期，还有 \(doc.daysToExpiry() ?? 0) 天。建议提前三个月办理换发。",
                               documentIDs: [doc.id])
        }
        if question.contains("保险") || question.contains("续") {
            let doc = documents[3]
            return VaultAnswer(answer: "外公的医疗保险还有 \(doc.daysToExpiry() ?? 0) 天到期，需要续保。保单和联系电话在这份文件里。",
                               documentIDs: [doc.id])
        }
        if question.contains("体检") {
            return VaultAnswer(answer: "外婆最近一次体检：血压略高，医生建议三个月后复查。", documentIDs: ["checkup-grandma"])
        }
        return nil
    }
}
