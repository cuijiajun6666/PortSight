//
//  DemoFamilyFiles.swift
//  PortSight
//
//  Fictional folders and files for the family edition's 文件 page (the Mac mini's shared drive). Names, sizes
//  and dates are made up; nothing is read from disk.
//

import Foundation

public struct FamilyFile: Identifiable, Hashable {
    public enum Kind: String {
        case pdf, document, spreadsheet, image, video, archive

        public var icon: String {
            switch self {
            case .pdf: "doc.richtext"
            case .document: "doc.text"
            case .spreadsheet: "tablecells"
            case .image: "photo"
            case .video: "film"
            case .archive: "archivebox"
            }
        }
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let sizeMB: Double
    public let modified: Date
    public let ownerID: String
}

public struct FamilyFolder: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let icon: String
    public let files: [FamilyFile]

    public var sizeMB: Double { files.reduce(0) { $0 + $1.sizeMB } }
}

public enum DemoFamilyFiles {
    private static func ago(_ days: Double) -> Date { Date().addingTimeInterval(-days * 86_400) }

    public static let usedGB = 412.6
    public static let totalGB = 2_000.0

    public static let folders: [FamilyFolder] = [
        FamilyFolder(id: "home", name: "家里的文档", icon: "house", files: [
            FamilyFile(id: "f1", name: "2026 年家庭开支.xlsx", kind: .spreadsheet, sizeMB: 0.4, modified: ago(0.3), ownerID: "mom"),
            FamilyFile(id: "f2", name: "装修合同.pdf", kind: .pdf, sizeMB: 3.2, modified: ago(46), ownerID: "dad"),
            FamilyFile(id: "f3", name: "家电说明书合集.zip", kind: .archive, sizeMB: 88, modified: ago(210), ownerID: "dad"),
        ]),
        FamilyFolder(id: "scans", name: "扫描件", icon: "doc.viewfinder", files: [
            FamilyFile(id: "f4", name: "外婆体检报告.pdf", kind: .pdf, sizeMB: 6.8, modified: ago(40), ownerID: "grandma"),
            FamilyFile(id: "f5", name: "老相册第 3 本.pdf", kind: .pdf, sizeMB: 142, modified: ago(95), ownerID: "mom"),
        ]),
        FamilyFolder(id: "videos", name: "视频素材", icon: "film.stack", files: [
            FamilyFile(id: "f6", name: "春节年夜饭.mov", kind: .video, sizeMB: 1_840, modified: ago(270), ownerID: "me"),
            FamilyFile(id: "f7", name: "外公八十大寿.mp4", kind: .video, sizeMB: 2_310, modified: ago(400), ownerID: "dad"),
        ]),
        FamilyFolder(id: "school", name: "表妹的学习资料", icon: "graduationcap", files: [
            FamilyFile(id: "f8", name: "英语作文.docx", kind: .document, sizeMB: 0.2, modified: ago(2), ownerID: "cousin"),
            FamilyFile(id: "f9", name: "画画作品.jpg", kind: .image, sizeMB: 4.1, modified: ago(5), ownerID: "cousin"),
        ]),
    ]

    /// Most recently changed files across all folders.
    public static var recent: [FamilyFile] {
        Array(folders.flatMap(\.files).sorted { $0.modified > $1.modified }.prefix(4))
    }

    public static func sizeTitle(_ mb: Double) -> String {
        mb >= 1_000 ? String(format: "%.1f GB", mb / 1_000) : mb >= 1 ? String(format: "%.0f MB", mb) : String(format: "%.0f KB", mb * 1_000)
    }
}
