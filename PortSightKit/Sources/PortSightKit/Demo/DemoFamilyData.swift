//
//  DemoFamilyData.swift
//  PortSight
//
//  Fictional photo library for the family edition (家人版): people, photos, places, auto albums, "on this day",
//  duplicates and photo Q&A. It mirrors what Immich provides (CLIP search, faces, map, memories, duplicates) and
//  what a local vision model would add (captions, Q&A, story albums, era estimates). No real photos or people.
//

import Foundation

public struct FamilyPerson: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let relation: String
    public let symbol: String
    public let hue: Double
    public let birthYear: Int
}

public struct FamilyPlace: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
}

public nonisolated struct FamilyPhoto: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let date: Date
    public let peopleIDs: [String]
    public let placeID: String?
    /// Caption written by the local vision model (第二层); search falls back to it.
    public let caption: String
    public let symbol: String
    public let hue: Double
    public let isVideo: Bool
    /// Estimated decade for scanned old photos, when the date is unknown.
    public let estimatedEra: String?
    /// Set for photos from the family's Immich library (FamilyLibrary); nil in the demo library.
    public let remote: FamilyRemoteAsset?

    public init(id: String, date: Date, peopleIDs: [String], placeID: String?, caption: String, symbol: String,
                hue: Double, isVideo: Bool, estimatedEra: String?, remote: FamilyRemoteAsset? = nil) {
        self.id = id
        self.date = date
        self.peopleIDs = peopleIDs
        self.placeID = placeID
        self.caption = caption
        self.symbol = symbol
        self.hue = hue
        self.isVideo = isVideo
        self.estimatedEra = estimatedEra
        self.remote = remote
    }
}

/// What the app needs to draw an Immich photo: `id` is the Immich asset id.
public nonisolated struct FamilyRemoteAsset: Hashable, Sendable, Codable {
    /// Width / height, so the viewer can place the picture before it has loaded.
    public let ratio: Double
    /// Milliseconds, for videos.
    public let durationMs: Int?
    /// The hidden video of a Live Photo.
    public let livePhotoVideoID: String?
    public let city: String?
    /// Hours east of UTC where it was taken (0 when unknown).
    public let localOffsetHours: Double

    public init(ratio: Double, durationMs: Int?, livePhotoVideoID: String?, city: String?, localOffsetHours: Double) {
        self.ratio = ratio
        self.durationMs = durationMs
        self.livePhotoVideoID = livePhotoVideoID
        self.city = city
        self.localOffsetHours = localOffsetHours
    }

    /// Where it was taken, as an offset from UTC: its date and time show in the photographer's clock time, the
    /// same wherever the phone is.
    public var timeZone: TimeZone {
        TimeZone(secondsFromGMT: Int((localOffsetHours * 3600).rounded())) ?? .gmt
    }
}

public struct FamilyAlbum: Identifiable, Hashable {
    public enum Kind: String { case trip = "旅行", festival = "节日", everyday = "日常" }
    public let id: String
    public let title: String
    public let kind: Kind
    public let story: String
    public let photoIDs: [String]
}

public struct FamilyDuplicateGroup: Identifiable, Hashable {
    public let id: String
    public let photoIDs: [String]
    public let reason: String
    public let savingMB: Double
}

public struct FamilyAnswer: Identifiable, Hashable {
    public let id: String
    public let question: String
    public let answer: String
    public let photoIDs: [String]
}

public enum DemoFamilyData {
    public static let people: [FamilyPerson] = [
        FamilyPerson(id: "mom", name: "妈妈", relation: "家人", symbol: "heart.fill", hue: 0.95, birthYear: 1968),
        FamilyPerson(id: "dad", name: "爸爸", relation: "家人", symbol: "figure.walk", hue: 0.58, birthYear: 1966),
        FamilyPerson(id: "grandpa", name: "外公", relation: "长辈", symbol: "cup.and.saucer.fill", hue: 0.08, birthYear: 1941),
        FamilyPerson(id: "grandma", name: "外婆", relation: "长辈", symbol: "leaf.fill", hue: 0.33, birthYear: 1944),
        FamilyPerson(id: "me", name: "我", relation: "自己", symbol: "person.fill", hue: 0.66, birthYear: 1998),
        FamilyPerson(id: "cousin", name: "表妹", relation: "亲戚", symbol: "star.fill", hue: 0.82, birthYear: 2008),
    ]

    public static let places: [FamilyPlace] = [
        FamilyPlace(id: "sydney", name: "悉尼", latitude: -33.8688, longitude: 151.2093),
        FamilyPlace(id: "bondi", name: "邦迪海滩", latitude: -33.8915, longitude: 151.2767),
        FamilyPlace(id: "shanghai", name: "上海", latitude: 31.2304, longitude: 121.4737),
        FamilyPlace(id: "hangzhou", name: "杭州西湖", latitude: 30.2431, longitude: 120.1503),
        FamilyPlace(id: "beijing", name: "北京", latitude: 39.9042, longitude: 116.4074),
        FamilyPlace(id: "oldhouse", name: "老家", latitude: 29.8683, longitude: 121.5440),
        FamilyPlace(id: "tokyo", name: "东京", latitude: 35.6762, longitude: 139.6503),
    ]

    private static let calendar = Calendar(identifier: .gregorian)
    private static func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The day the demo treats as "today" for 那年今日 (the app's real date in the month/day sense).
    private static var todayParts: (month: Int, day: Int) {
        let parts = calendar.dateComponents([.month, .day], from: Date())
        return (parts.month ?? 1, parts.day ?? 1)
    }

    public static let photos: [FamilyPhoto] = {
        var list: [FamilyPhoto] = []
        func add(_ id: String, _ date: Date, _ people: [String], _ place: String?, _ caption: String, _ symbol: String,
                 _ hue: Double, video: Bool = false, era: String? = nil) {
            list.append(FamilyPhoto(id: id, date: date, peopleIDs: people, placeID: place, caption: caption, symbol: symbol,
                                    hue: hue, isVideo: video, estimatedEra: era))
        }
        // Old scans: dates unknown, era estimated by the vision model.
        add("o1", day(1972, 1, 1), ["grandpa", "grandma"], "oldhouse", "黑白照片，外公外婆在老房子门口的合影", "house", 0.08, era: "约 1970 年代")
        add("o2", day(1975, 1, 1), ["mom"], "oldhouse", "扎两个小辫的小女孩坐在竹椅上", "chair", 0.1, era: "约 1970 年代")
        add("o3", day(1988, 1, 1), ["mom", "dad"], "hangzhou", "西湖断桥边的合影，衣服是八十年代的款式", "water.waves", 0.55, era: "约 1980 年代")
        // Family timeline.
        add("p1", day(1999, 2, 16), ["me", "mom"], "oldhouse", "过年在老房子门口贴春联，婴儿裹着红色襁褓", "seal.fill", 0.0)
        add("p2", day(2005, 6, 1), ["me"], "shanghai", "儿童节在公园放风筝", "wind", 0.5)
        add("p3", day(2008, 8, 8), ["me", "dad"], "beijing", "一起在电视前看奥运开幕式", "tv", 0.6)
        add("p4", day(2010, 10, 1), ["grandpa", "me"], "oldhouse", "外公教我下象棋", "checkerboard.rectangle", 0.12)
        add("p5", day(2012, 2, 4), ["grandma", "cousin"], "oldhouse", "外婆在厨房包饺子，表妹在旁边捣乱", "fork.knife", 0.3)
        add("p6", day(2015, 4, 12), ["mom", "dad"], "tokyo", "妈妈在东京看樱花，穿浅蓝色外套", "camera.macro", 0.92)
        add("p7", day(2015, 4, 13), ["mom"], "tokyo", "浅草寺门口的大红灯笼", "lamp.table", 0.02)
        add("p8", day(2015, 9, 27), ["mom", "dad", "grandpa", "grandma"], "shanghai", "中秋节一家人吃月饼赏月", "moon.stars.fill", 0.15)
        add("p9", day(2018, 2, 15), ["grandpa", "grandma", "mom", "me"], "oldhouse", "除夕年夜饭，外公举杯", "wineglass", 0.98)
        add("p10", day(2019, 7, 20), ["me"], "sydney", "第一次到悉尼，歌剧院前的自拍", "building.columns", 0.56)
        add("p11", day(2022, 1, 1), ["me", "cousin"], "bondi", "邦迪海滩的日落，两个人的剪影", "sunset.fill", 0.07)
        add("p12", day(2022, 1, 1), ["me", "cousin"], "bondi", "邦迪海滩的日落（连拍）", "sunset.fill", 0.07)
        add("p13", day(2023, 10, 31), ["me"], "sydney", "万圣节，公寓楼下的南瓜灯", "flame", 0.08)
        add("p14", day(2024, 2, 10), ["mom", "dad", "me"], "shanghai", "春节回家，穿红衣服的表妹在放烟花", "sparkles", 0.0)
        add("p15", day(2024, 5, 12), ["mom"], "shanghai", "母亲节的生日蛋糕，写着「妈妈节日快乐」", "birthday.cake", 0.9)
        add("p16", day(2025, 4, 5), ["grandpa", "me"], "hangzhou", "陪外公在西湖边散步", "figure.walk", 0.4, video: true)
        add("p17", day(2025, 12, 25), ["me", "cousin"], "sydney", "圣诞节海边烧烤", "flame.fill", 0.03)
        add("p18", day(2026, 1, 26), ["me"], "sydney", "澳洲国庆日的烟花", "sparkles", 0.62, video: true)
        // "On this day" for whatever today is, in three earlier years.
        let today = todayParts
        add("t1", day(2016, today.month, today.day), ["mom", "grandma"], "oldhouse", "那年今天，妈妈和外婆在院子里晒被子", "sun.max.fill", 0.13)
        add("t2", day(2020, today.month, today.day), ["me"], "sydney", "那年今天，在悉尼的第一个秋天", "leaf.fill", 0.09)
        add("t3", day(2023, today.month, today.day), ["me", "cousin"], "bondi", "那年今天，海边冲浪课", "figure.surfing", 0.53)
        return list.sorted { $0.date > $1.date }
    }()

    public static let albums: [FamilyAlbum] = [
        FamilyAlbum(id: "tokyo2015", title: "2015 · 东京赏樱", kind: .trip,
                    story: "四月的东京，妈妈第一次出国。樱花正好，浅草寺的灯笼比想象中大。", photoIDs: ["p6", "p7"]),
        FamilyAlbum(id: "springfestival", title: "这些年的春节", kind: .festival,
                    story: "从老房子门口的春联，到上海家里的烟花，一家人每年都聚在一起。", photoIDs: ["p1", "p9", "p14"]),
        FamilyAlbum(id: "bondi", title: "邦迪海滩", kind: .trip,
                    story: "日落、冲浪和烧烤，悉尼最常去的地方。", photoIDs: ["p11", "t3", "p17"]),
        FamilyAlbum(id: "grandpa", title: "和外公在一起", kind: .everyday,
                    story: "象棋、年夜饭、西湖边的散步。", photoIDs: ["p4", "p9", "p16"]),
    ]

    public static let duplicates: [FamilyDuplicateGroup] = [
        FamilyDuplicateGroup(id: "d1", photoIDs: ["p11", "p12"], reason: "连拍，几乎相同", savingMB: 6.4),
    ]

    public static let answers: [FamilyAnswer] = [
        FamilyAnswer(id: "q1", question: "妈妈 2015 年去过哪些地方？",
                     answer: "2015 年妈妈去过东京（4 月，看樱花、逛浅草寺）和上海（9 月，中秋节全家团聚）。",
                     photoIDs: ["p6", "p7", "p8"]),
        FamilyAnswer(id: "q2", question: "外公最早的一张照片是哪年的？",
                     answer: "最早的一张是外公外婆在老房子门口的黑白合影，没有拍摄日期，从照片质感和衣着估计在 1970 年代。",
                     photoIDs: ["o1"]),
        FamilyAnswer(id: "q3", question: "我们一共过了几个有照片的春节？",
                     answer: "相册里有 3 个春节：1999 年在老家、2018 年除夕年夜饭、2024 年回上海。",
                     photoIDs: ["p1", "p9", "p14"]),
    ]

    public static let searchSuggestions = ["海边的日落", "穿红衣服的小孩", "生日蛋糕", "妈妈和外公的合照", "过年贴春联", "樱花"]

    public static func person(_ id: String) -> FamilyPerson? { people.first { $0.id == id } }
    public static func place(_ id: String?) -> FamilyPlace? { places.first { $0.id == id } }
    public static func photo(_ id: String) -> FamilyPhoto? { photos.first { $0.id == id } }

    public static func photos(of personID: String) -> [FamilyPhoto] {
        photos.filter { $0.peopleIDs.contains(personID) }
    }

    public static func photos(at placeID: String) -> [FamilyPhoto] {
        photos.filter { $0.placeID == placeID }
    }

    /// 那年今日: earlier years' photos taken on today's month and day.
    public static var onThisDay: [FamilyPhoto] {
        let today = todayParts
        let thisYear = calendar.component(.year, from: Date())
        return photos.filter {
            let parts = calendar.dateComponents([.year, .month, .day], from: $0.date)
            return parts.month == today.month && parts.day == today.day && (parts.year ?? thisYear) < thisYear
        }
    }

    /// Photos grouped by year, newest first, for the library grid (dated photos only; old scans live in 回忆).
    public static var byYear: [(title: String, photos: [FamilyPhoto])] {
        let groups = Dictionary(grouping: photos.filter { $0.estimatedEra == nil }) { calendar.component(.year, from: $0.date) }
        return groups.keys.sorted(by: >).map { ("\($0) 年", groups[$0] ?? []) }
    }

    public static var oldPhotos: [FamilyPhoto] { photos.filter { $0.estimatedEra != nil } }

    /// Demo of CLIP + caption search: scores each photo by how many of the query's characters appear in its
    /// caption, people and place, best matches first. The real search runs in Immich (multilingual CLIP).
    public static func search(_ query: String) -> [FamilyPhoto] {
        let ignored: Set<Character> = ["的", "和", "在", "了", "张", "照", "片", " "]
        let chars = Set(query.filter { !ignored.contains($0) })
        guard !chars.isEmpty else { return [] }
        let scored: [(FamilyPhoto, Double)] = photos.map { photo in
            let names = photo.peopleIDs.compactMap { person($0)?.name }.joined()
            let haystack = photo.caption + names + (place(photo.placeID)?.name ?? "")
            let hits = chars.filter { haystack.contains($0) }.count
            return (photo, Double(hits) / Double(chars.count))
        }
        return scored.filter { $0.1 >= 0.6 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Demo of photo Q&A: a prepared answer when the question is close to one of them.
    public static func answer(_ question: String) -> FamilyAnswer? {
        answers.first { candidate in
            let keys = ["妈妈", "外公", "春节", "2015", "最早"].filter { candidate.question.contains($0) }
            return keys.contains { question.contains($0) }
        }
    }

    /// 成长时间线: one photo per year for a person, oldest first.
    public static func timeline(of personID: String) -> [(year: String, photo: FamilyPhoto)] {
        let list = photos(of: personID).sorted { $0.date < $1.date }
        var seen = Set<String>()
        return list.compactMap { photo in
            let year = photo.estimatedEra ?? "\(calendar.component(.year, from: photo.date))"
            return seen.insert(year).inserted ? (year, photo) : nil
        }
    }
}
