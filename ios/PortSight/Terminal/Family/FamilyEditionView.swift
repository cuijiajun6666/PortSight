//
//  FamilyEditionView.swift
//  PortSight
//
//  家人版: the app reduced to the family photo library on the Mac mini (Immich). No assets, trading or server.
//  Tabs: 图库 (照片 / 文件) · 回忆 · 保险箱 · AI (人物 and 地图 sit in 回忆's toolbar). Features that need the local vision model are marked "本地大模型".
//  Demo data only; nothing connects.
//

import SwiftUI
import MapKit
import PhotosUI
import UniformTypeIdentifiers
import PortSightKit

/// Switch between the full terminal and the family edition (设置 → 家人版).
enum AppEdition {
    static let storageKey = "edition.family"
}

struct FamilyEditionView: View {
    @State private var selectedTab = 0
    @State private var libraryPage = FamilyLibraryPage.photos
    @State private var libraryZoom = FamilyLibraryZoom.all
    @State private var tabBarMinimized = false
    @State private var safeAreaBottom: CGFloat = 0
    /// Bumped when 图库 is tapped while already selected: the grid scrolls back to the newest photos.
    @State private var libraryReselected = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Like Photos: tapping the selected 图库 tab again returns to the newest photos.
    private var tabSelection: Binding<Int> {
        Binding(get: { selectedTab }, set: { new in
            if new == selectedTab && new == 0 { libraryReselected += 1 }
            selectedTab = new
        })
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("图库", systemImage: "photo.on.rectangle.angled", value: 0) {
                FamilyLibraryTab(page: $libraryPage, zoom: $libraryZoom, reselected: libraryReselected)
            }
            Tab("回忆", systemImage: "sparkles.rectangle.stack", value: 1) { FamilyMemoriesView() }
            Tab("保险箱", systemImage: "lock.shield", value: 3) { VaultView() }
            // Search tab slot, shown as AI: natural-language photo search and asking the album.
            // The system search tab: tapping it turns the separate button into a search field with the
            // keyboard up, as in the App Store. Photos and questions share that one field.
            Tab(value: 4, role: .search) {
                FamilySearchView()
            } label: {
                Label("AI", systemImage: "sparkles")
            }
        }
        // The photo grid opens at the bottom and is read upwards, so there the bar shrinks on scrolling up.
        .tabBarMinimizeBehaviorWithUpdate(isMinimized: $tabBarMinimized,
                                          behavior: showsLibraryPicker ? .onScrollUp : .onScrollDown,
                                          refresh: selectedTab) {}
        .tabViewSearchActivation(.searchTabSelection)
        .portSightScrollEdge()
        .sensoryFeedback(.selection, trigger: selectedTab)
        // As in Photos: once the bar is minimized, 年 / 月 / 全部 sits in the space it leaves (PhotosTB sample).
        .overlay(alignment: .bottom) {
            FamilyZoomPicker(selection: $libraryZoom)
            .opacity(tabBarMinimized && showsLibraryPicker ? 1 : 0)
            .allowsHitTesting(tabBarMinimized && showsLibraryPicker)
            .frame(maxWidth: 350)
            .offset(y: safeAreaBottom == 0 ? -28 : (horizontalSizeClass == .regular ? -3 : 6))
            // 48 for the minimized tab, 30 padding, a little extra.
            .padding(.horizontal, 85)
            .animation(.easeInOut(duration: 0.12), value: tabBarMinimized)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { safeAreaBottom = $0 }
        .sensoryFeedback(.selection, trigger: libraryZoom)
    }

    private var showsLibraryPicker: Bool { selectedTab == 0 && libraryPage == .photos }
}

// MARK: - Shared pieces

/// A photo: the Immich picture for the family's library, a stand-in picture for the demo library.
struct FamilyPhotoTile: View {
    let photo: FamilyPhoto
    var cornerRadius: CGFloat = 10
    var symbolFont: Font = .title2
    /// Square by default; cards let the tile fill whatever frame they give it.
    var square = true
    /// The full-screen viewer shows the whole picture (fit) without the grid's badges; tiles crop (fill).
    var fit = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                if photo.remote != nil {
                    FamilyRemoteImage(photo: photo, fit: fit)
                } else if let name = photo.demoImageName {
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: fit ? .fit : .fill)
                } else {
                    Image(systemName: photo.symbol)
                        .font(symbolFont)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if photo.isVideo && !fit {
                    Image(systemName: "play.fill").font(.caption2).foregroundStyle(.white).shadow(radius: 2).padding(6)
                }
            }
            .overlay(alignment: .topLeading) {
                if photo.estimatedEra != nil && !fit {
                    Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(.white).shadow(radius: 2).padding(6)
                }
            }
            .modifier(SquareTile(enabled: square))
            .accessibilityLabel(photo.accessibilityText)
    }

    private var fill: AnyShapeStyle {
        // Real pictures need no backdrop; one would show round the picture while it animates between
        // fill (grid) and fit (viewer).
        if photo.remote != nil || photo.demoImageName != nil { return AnyShapeStyle(.clear) }
        return AnyShapeStyle(LinearGradient(colors: [Color(hue: photo.hue, saturation: 0.35, brightness: 0.95),
                                                     Color(hue: photo.hue, saturation: 0.55, brightness: 0.75)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

extension FamilyPhoto {
    /// Stand-in pictures until Immich thumbnails are connected: five free Pexels photos (from the
    /// PhotosTransition sample) shared round the demo library, so they do not match the captions.
    var demoImageName: String? {
        "FamilyDemo\(id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 5 + 1)"
    }

    /// Width / height of the picture shown for this photo (1 for the drawn placeholders).
    var displayAspectRatio: CGFloat {
        if let remote { return CGFloat(remote.ratio) }
        guard let name = demoImageName, let image = UIImage(named: name), image.size.height > 0 else { return 1 }
        return image.size.width / image.size.height
    }

    /// VoiceOver: the caption, or for Immich photos (which have none) what and when.
    var accessibilityText: String {
        guard caption.isEmpty else { return caption }
        return (isVideo ? "视频，" : "照片，") + dateText(.dateTime.year().month().day())
    }

    /// The date for display: an Immich photo in the clock time where it was taken (the same wherever the phone
    /// is), a demo photo in the phone's time zone.
    func dateText(_ style: Date.FormatStyle) -> String {
        var style = style
        if let remote { style.timeZone = remote.timeZone }
        return date.formatted(style)
    }
}

private struct SquareTile: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.aspectRatio(1, contentMode: .fit) } else { content }
    }
}

struct FamilyPhotoGrid: View {
    let photos: [FamilyPhoto]
    var columns = 3

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: columns), spacing: 3) {
            ForEach(photos) { photo in
                NavigationLink { FamilyPhotoDetailView(photo: photo) } label: { FamilyPhotoTile(photo: photo, cornerRadius: 4) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Marks features that only arrive with the local vision model.
struct FamilyModelBadge: View {
    var body: some View {
        Label("本地大模型", systemImage: "cpu")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.purple.opacity(0.12), in: Capsule())
    }
}

struct FamilyPersonAvatar: View {
    let person: FamilyPerson
    var size: CGFloat = 64

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(hue: person.hue, saturation: 0.3, brightness: 0.98),
                                          Color(hue: person.hue, saturation: 0.55, brightness: 0.8)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay { Image(systemName: person.symbol).font(.system(size: size * 0.36)).foregroundStyle(.white) }
    }
}

func familyDate(_ date: Date) -> String { date.formatted(.dateTime.year().month().day()) }

// MARK: - 照片

enum FamilyLibraryPage: String, CaseIterable, Identifiable {
    case photos = "照片", files = "文件"
    var id: String { rawValue }
}

/// 图库 tab: 照片 and 文件, switched from the title menu in the navigation bar (blur-replace, state kept).
struct FamilyLibraryTab: View {
    @Binding var page: FamilyLibraryPage
    @Binding var zoom: FamilyLibraryZoom
    var reselected = 0

    var body: some View {
        KeptAlivePages(name: "图库", page: $page) { item in
            switch item {
            case .photos: FamilyLibraryView(zoom: $zoom, reselected: reselected)
            case .files: FamilyFilesView()
            }
        }
    }
}

/// Transient note at the bottom of a page, e.g. after picking files to upload.
private struct FamilyUploadToast: ViewModifier {
    @Binding var note: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let note {
                Label(note, systemImage: "icloud.and.arrow.up")
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal).padding(.bottom, 12)
                    .transition(.blurReplace)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        self.note = nil
                    }
            }
        }
        .animation(.smooth, value: note)
    }
}

struct FamilyLibraryView: View {
    @Binding var zoom: FamilyLibraryZoom
    var reselected = 0
    /// True for the moment between a card tap and the next level fading in at the chosen month. The
    /// scroll view moves to that month while nothing is shown, so no fading cards get dragged along.
    @State private var revealing = false
    @State private var position = ScrollPosition()
    @State private var showSettings = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var uploadNote: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            // Like Photos: oldest at the top, opening at the newest just above the tab bar. 年 / 月 / 全部
            // come from the picker beside the minimized tab bar; a card zooms into the next level. One
            // ScrollView for all three levels, so only the content changes and the navigation bar's edge
            // effect stays put.
            ScrollView(.vertical) {
                // Bottom-aligned: while one level replaces the other, both keep their newest end at the
                // bottom, so the height change happens above what is on screen and nothing jumps.
                ZStack(alignment: .bottom) {
                    switch zoom {
                    case .years:
                        FamilyLibraryCards(groups: FamilyLibraryCards.years(of: library), tall: true) { year in
                            open(.months, at: year.target)
                        }
                        .transition(.blurReplace)
                    case .months:
                        FamilyLibraryCards(groups: FamilyLibraryCards.months(of: library), tall: false) { month in
                            open(.all, at: month.target)
                        }
                        .transition(.blurReplace)
                    case .all:
                        FamilyHeroGrid(slots: library.slots, position: $position)
                            .transition(.blurReplace)
                    }
                }
                .animation(.smooth(duration: 0.35), value: zoom)
                .blur(radius: revealing ? 12 : 0)
                .opacity(revealing ? 0 : 1)
            }
            .defaultScrollAnchor(.bottom)
            // While one level blur-replaces the other the content height changes; stay at the newest end.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollPosition($position)
            .overlay { libraryState }
            .portSightHeader("照片", caption: caption)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The shared library, so each item carries its asset identifier: the upload sends the
                    // original resources (HEIC, Live Photo video, original video), not a re-encoded copy.
                    PhotosPicker(selection: $picked, matching: .any(of: [.images, .videos]), photoLibrary: .shared()) {
                        Image(systemName: "icloud.and.arrow.up")
                    }
                    .accessibilityLabel("上传照片")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                let ids = items.compactMap(\.itemIdentifier)
                picked = []
                Task {
                    uploadNote = await DriveUploader.shared.enqueue(assetIDs: ids)
                    if DriveUploader.needsSetup { showSettings = true }
                }
            }
            .modifier(FamilyUploadToast(note: $uploadNote))
            .sheet(isPresented: $showSettings) { FamilySettingsView() }
            .onChange(of: reselected) { _, _ in scrollToNewest() }
            .task {
                // The uploader first: on a reinstall it removes a configuration left in the keychain.
                _ = DriveUploader.shared
                library.start()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { library.start() }
            }
        }
    }

    /// The family's Immich library when configured, otherwise the demo library.
    private var library: FamilyLibrary { FamilyLibrary.shared }

    private var caption: String? {
        if case .failed(let error) = library.status, !library.months.isEmpty {
            // A refused key is the admin's to fix; anything else is usually the proxy being off.
            return error == .unauthorized || error == .forbidden ? "钥匙失效 · 显示上次的照片" : "未连接 · 显示上次的照片"
        }
        return library.newestPhoto?.dateText(.dateTime.year().month().day())
    }

    /// Connecting, unreachable or empty, while there is nothing to show yet.
    @ViewBuilder private var libraryState: some View {
        if library.isRemote && library.months.isEmpty {
            switch library.status {
            case .failed(let error):
                ContentUnavailableView {
                    Label("连不上照片库", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("重试") { library.refresh() }
                        .buttonStyle(.glass)
                }
            case .ready:
                ContentUnavailableView("照片库还是空的", systemImage: "photo.on.rectangle",
                                       description: Text("家人上传的照片整理进照片库后会出现在这里。"))
            case .connecting, .demo:
                ProgressView("正在连接照片库…")
            }
        }
    }

    /// Back to the newest end of the current level, as when the 图库 tab is tapped again.
    private func scrollToNewest() {
        let newest: String? = switch zoom {
        case .years: FamilyLibraryCards.years(of: library).last?.id
        case .months: library.months.last?.id
        case .all: library.slots.last?.id
        }
        guard let newest else { return }
        withAnimation(.smooth(duration: 0.45)) { position.scrollTo(id: newest, anchor: .bottom) }
    }

    /// Picker switches need no scrolling: levels are bottom-aligned, so the newest ends stay put while one
    /// blur-replaces the other. A card swaps levels at once, scrolls to its month while hidden, then fades
    /// the new level in.
    private func open(_ level: FamilyLibraryZoom, at target: String?) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            revealing = true
            zoom = level
        }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            if let target { position.scrollTo(id: target, anchor: .top) }
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.smooth(duration: 0.35)) { revealing = false }
        }
    }
}

// MARK: - 文件

struct FamilyFilesView: View {
    @State private var showSettings = false
    @State private var importing = false
    @State private var uploadNote: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Mac mini 家庭盘").font(.headline)
                            Spacer()
                            Text(String(format: "%.0f GB / %.0f TB", DemoFamilyFiles.usedGB, DemoFamilyFiles.totalGB / 1_000))
                                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        ProgressView(value: DemoFamilyFiles.usedGB, total: DemoFamilyFiles.totalGB)
                    }
                    .padding(.vertical, 4)
                }

                Section("文件夹") {
                    ForEach(DemoFamilyFiles.folders) { folder in
                        NavigationLink { FamilyFolderView(folder: folder) } label: {
                            LabeledContent {
                                Text("\(folder.files.count) 项")
                            } label: {
                                Label(folder.name, systemImage: folder.icon)
                            }
                        }
                    }
                }

                Section("最近") {
                    ForEach(DemoFamilyFiles.recent) { FamilyFileRow(file: $0) }
                }
            }
            .listStyle(.insetGrouped)
            .portSightHeader("文件", caption: "\(DemoFamilyFiles.folders.count) 个文件夹 · 家庭盘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "icloud.and.arrow.up") }
                        .accessibilityLabel("上传文件")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("设置")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result, !urls.isEmpty {
                    uploadNote = "已选 \(urls.count) 个文件，正在后台上传"
                }
            }
            .modifier(FamilyUploadToast(note: $uploadNote))
            .sheet(isPresented: $showSettings) { FamilySettingsView() }
        }
    }
}

struct FamilyFolderView: View {
    let folder: FamilyFolder

    var body: some View {
        List {
            Section {
                ForEach(folder.files) { FamilyFileRow(file: $0) }
            } footer: {
                Text("\(folder.files.count) 项 · " + DemoFamilyFiles.sizeTitle(folder.sizeMB))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FamilyFileRow: View {
    let file: FamilyFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.kind.icon)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text([DemoFamilyData.person(file.ownerID)?.name ?? "",
                      file.modified.formatted(.relative(presentation: .named)),
                      DemoFamilyFiles.sizeTitle(file.sizeMB)].joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FamilyPhotoDetailView: View {
    let photo: FamilyPhoto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FamilyPhotoTile(photo: photo, cornerRadius: 22)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(photo.estimatedEra ?? familyDate(photo.date)).font(.title3.bold())
                        Spacer()
                        if photo.estimatedEra != nil { FamilyModelBadge() }
                    }
                    if let place = DemoFamilyData.place(photo.placeID) {
                        Label(place.name, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("照片描述").font(.headline)
                        Spacer()
                        FamilyModelBadge()
                    }
                    Text(photo.caption).foregroundStyle(.secondary)
                }
                if !photo.peopleIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("照片里的人").font(.headline)
                        ScrollView(.horizontal) {
                            HStack(spacing: 14) {
                                ForEach(photo.peopleIDs.compactMap(DemoFamilyData.person)) { person in
                                    NavigationLink { FamilyPersonView(person: person) } label: {
                                        VStack(spacing: 6) {
                                            FamilyPersonAvatar(person: person, size: 52)
                                            Text(person.name).font(.caption).foregroundStyle(.primary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(photo.isVideo ? "视频" : "照片")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 回忆

struct FamilyMemoriesView: View {
    var body: some View {
        NavigationStack {
            List {
                if !DemoFamilyData.onThisDay.isEmpty {
                    Section("那年今日") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(DemoFamilyData.onThisDay) { photo in
                                    NavigationLink { FamilyPhotoDetailView(photo: photo) } label: {
                                        FamilyPhotoTile(photo: photo, cornerRadius: 18)
                                            .frame(width: 220)
                                            .overlay(alignment: .bottomLeading) {
                                                Text(yearsAgo(photo.date))
                                                    .font(.headline).foregroundStyle(.white)
                                                    .padding(12)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    ForEach(DemoFamilyData.albums) { album in
                        NavigationLink { FamilyAlbumView(album: album) } label: {
                            HStack(spacing: 14) {
                                if let cover = album.photoIDs.first.flatMap(DemoFamilyData.photo) {
                                    FamilyPhotoTile(photo: cover, cornerRadius: 12).frame(width: 64)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(album.title).font(.headline)
                                    Text(album.story).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    Text(album.kind.rawValue + " · \(album.photoIDs.count) 项").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack { Text("自动相册"); Spacer(); FamilyModelBadge() }
                } footer: {
                    Text("按一次旅行、一个节日自动成册，每张配一段说明。")
                }

                Section {
                    ForEach(DemoFamilyData.oldPhotos) { photo in
                        NavigationLink { FamilyPhotoDetailView(photo: photo) } label: {
                            HStack(spacing: 14) {
                                FamilyPhotoTile(photo: photo, cornerRadius: 10).frame(width: 52)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(photo.estimatedEra ?? "").font(.subheadline.weight(.semibold))
                                    Text(photo.caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                } header: {
                    HStack { Text("老照片"); Spacer(); FamilyModelBadge() }
                } footer: {
                    Text("没有拍摄日期的扫描照片，按画面估计年代。")
                }

                Section {
                    ForEach(DemoFamilyData.duplicates) { group in
                        HStack(spacing: 10) {
                            ForEach(group.photoIDs.compactMap(DemoFamilyData.photo)) { photo in
                                FamilyPhotoTile(photo: photo, cornerRadius: 8).frame(width: 52)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.reason).font(.subheadline)
                                Text(String(format: "可节省 %.1f MB", group.savingMB)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("保留一张") {}.buttonStyle(.glass).disabled(true)
                        }
                    }
                } header: {
                    Text("重复照片")
                } footer: {
                    Text("清理连拍和重复备份。Mac mini 到位后可用。")
                }
            }
            .listStyle(.insetGrouped)
            .portSightHeader("回忆", caption: "\(DemoFamilyData.albums.count) 个自动相册 · 那年今日")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { FamilyPeopleView() } label: { Image(systemName: "person.2") }
                        .accessibilityLabel("人物")
                    NavigationLink { FamilyMapView() } label: { Image(systemName: "map") }
                        .accessibilityLabel("照片地图")
                }
            }
        }
    }

    private func yearsAgo(_ date: Date) -> String {
        let years = Calendar.current.dateComponents([.year], from: date, to: .now).year ?? 0
        return years <= 0 ? "今天" : "\(years) 年前"
    }
}

struct FamilyAlbumView: View {
    let album: FamilyAlbum

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(album.story).font(.body).foregroundStyle(.secondary).padding(.horizontal)
                ForEach(album.photoIDs.compactMap(DemoFamilyData.photo)) { photo in
                    NavigationLink { FamilyPhotoDetailView(photo: photo) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            FamilyPhotoTile(photo: photo, cornerRadius: 18)
                            Text(photo.caption).font(.subheadline)
                            Text(photo.estimatedEra ?? familyDate(photo.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(album.title)
    }
}

// MARK: - 人物

/// Pushed from 回忆's toolbar.
struct FamilyPeopleView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 18)], spacing: 22) {
                ForEach(DemoFamilyData.people) { person in
                    NavigationLink { FamilyPersonView(person: person) } label: {
                        VStack(spacing: 8) {
                            FamilyPersonAvatar(person: person, size: 84)
                            Text(person.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("\(DemoFamilyData.photos(of: person.id).count) 张").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            Text("人脸由 Immich 自动分组，起好名字后就能按人看照片，也能搜「妈妈和外公的合照」。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
        }
        .navigationTitle("人物")
    }
}

struct FamilyPersonView: View {
    let person: FamilyPerson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    FamilyPersonAvatar(person: person, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(.title2.bold())
                        Text("\(person.relation) · \(DemoFamilyData.photos(of: person.id).count) 张照片").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("成长时间线").font(.headline); Spacer(); FamilyModelBadge() }
                    ForEach(DemoFamilyData.timeline(of: person.id), id: \.photo.id) { entry in
                        NavigationLink { FamilyPhotoDetailView(photo: entry.photo) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                VStack(spacing: 0) {
                                    Circle().fill(Color(hue: person.hue, saturation: 0.6, brightness: 0.85)).frame(width: 10, height: 10)
                                    Rectangle().fill(.quaternary).frame(width: 2).frame(maxHeight: .infinity)
                                }
                                .frame(width: 10)
                                FamilyPhotoTile(photo: entry.photo, cornerRadius: 10).frame(width: 72)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.year).font(.subheadline.weight(.semibold))
                                    Text(entry.photo.caption).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("全部照片").font(.headline).padding(.horizontal)
                    FamilyPhotoGrid(photos: DemoFamilyData.photos(of: person.id))
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 地图

struct FamilyMapView: View {
    @State private var selected: FamilyPlace?

    var body: some View {
        Group {
            Map {
                ForEach(DemoFamilyData.places.filter { !DemoFamilyData.photos(at: $0.id).isEmpty }) { place in
                    Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)) {
                        Button { selected = place } label: {
                            if let cover = DemoFamilyData.photos(at: place.id).first {
                                FamilyPhotoTile(photo: cover, cornerRadius: 10)
                                    .frame(width: 44)
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(DemoFamilyData.photos(at: place.id).count)")
                                            .font(.caption2.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.blue, in: Capsule())
                                            .offset(x: 6, y: -6)
                                    }
                                    .shadow(radius: 3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .navigationTitle("地图")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { place in
                NavigationStack {
                    ScrollView { FamilyPhotoGrid(photos: DemoFamilyData.photos(at: place.id)).padding(.vertical) }
                        .navigationTitle(place.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

// MARK: - 搜索

struct FamilySearchView: View {
    @State private var query = ""

    private var results: [FamilyPhoto] { DemoFamilyData.search(query) }
    private var answer: FamilyAnswer? { DemoFamilyData.answer(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if query.isEmpty {
                        suggestions
                    } else if answer == nil && results.isEmpty {
                        ContentUnavailableView("还找不到", systemImage: "sparkles",
                                               description: Text("换个说法试试，比如地点、人物或年份。"))
                    } else {
                        if answer != nil { askResult }
                        if answer == nil {
                            Text("\(results.count) 张").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                            FamilyPhotoGrid(photos: results)
                        }
                    }
                }
                .padding(.vertical)
            }
            .portSightHeader("AI", caption: "搜照片，或者问问相册")
        }
        .searchable(text: $query, prompt: "搜照片，或者问问相册")
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("可以这样搜，也可以直接问").font(.headline)
                Spacer()
                FamilyModelBadge()
            }
            ForEach(DemoFamilyData.searchSuggestions.prefix(4), id: \.self) { item in
                suggestion(item, icon: "magnifyingglass")
            }
            ForEach(DemoFamilyData.answers.map(\.question), id: \.self) { item in
                suggestion(item, icon: "text.bubble")
            }
            Text("画面用多语言 CLIP 模型搜，问题由本地大模型根据照片的时间、地点、人物回答。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func suggestion(_ text: String, icon: String) -> some View {
        Button { query = text } label: {
            Label(text, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder private var askResult: some View {
        if let answer {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label("回答", systemImage: "sparkles").font(.headline); Spacer(); FamilyModelBadge() }
                Text(answer.answer)
                Text("依据这些照片").font(.subheadline.weight(.semibold)).padding(.top, 4)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
            FamilyPhotoGrid(photos: answer.photoIDs.compactMap(DemoFamilyData.photo))
        }
    }
}

// MARK: - 设置

struct FamilySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppEdition.storageKey) private var familyEdition = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("家人版", isOn: $familyEdition)
                } footer: {
                    Text("家人版只显示照片和回忆。关掉后回到完整版（资产、交易、服务器）。")
                }
                FamilyDriveUploadSection()
                Section("服务器连接") {
                    ConnectionSettingsRow(status: DemoConnection.family)
                }
                FamilyLibrarySection()
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

/// 设置 → 照片库: the Immich connection once the configuration has one.
struct FamilyLibrarySection: View {
    private var library: FamilyLibrary { FamilyLibrary.shared }

    var body: some View {
        Section {
            if library.isRemote {
                LabeledContent("状态", value: status)
                LabeledContent("照片和视频", value: library.totalCount.formatted())
                LabeledContent("服务器", value: library.host ?? "")
                if case .failed = library.status {
                    Button("重新连接") { library.refresh() }
                }
            } else {
                LabeledContent("照片", value: DemoFamilyData.photos.filter { !$0.isVideo }.count.formatted())
                LabeledContent("视频", value: DemoFamilyData.photos.filter(\.isVideo).count.formatted())
                LabeledContent("人物", value: DemoFamilyData.people.count.formatted())
                LabeledContent("Immich", value: "尚未接入")
            }
        } header: {
            Text("照片库")
        } footer: {
            if library.isRemote {
                Text("照片从家里 Mac mini 上的 Immich 读取，需要打开翻墙。看过的照片会存在这台 iPhone 上，没连上时也能看。")
            } else {
                Text("管理员发来的配置里带上照片库后，图库会显示家里的照片。")
            }
        }
    }

    private var status: String {
        switch library.status {
        case .ready: "已连接"
        case .connecting: "正在连接"
        case .failed(let error): error.message
        case .demo: "尚未接入"
        }
    }
}

/// 年 / 月 / 全部, as in Photos: a glass capsule whose selected segment is a soft material thumb (not the
/// segmented control's solid white one) that slides between the options.
struct FamilyZoomPicker: View {
    @Binding var selection: FamilyLibraryZoom
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FamilyLibraryZoom.allCases) { zoom in
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selection = zoom }
                } label: {
                    Text(zoom.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == zoom {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == zoom ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("显示方式")
    }
}
