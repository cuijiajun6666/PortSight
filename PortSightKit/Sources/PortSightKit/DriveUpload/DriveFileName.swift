import Foundation

/// Unique Drive file names (contract §4): `<拍摄时间 yyyyMMdd_HHmmss>_<资源 ID 前 8 位>_<原文件名>`.
public nonisolated enum DriveFileName {
    /// "<yyyyMMdd_HHmmss>_<first 8 alphanumerics of assetID, lowercased>_<originalName>" in `timeZone`.
    /// A Live Photo's photo and paired video share the prefix.
    public static func make(takenAt: Date, assetID: String, originalName: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: takenAt)

        let idPart = String(assetID.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(8)).lowercased()

        var name = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        if name.isEmpty { name = "file" }

        return "\(stamp)_\(idPart)_\(name)"
    }
}
