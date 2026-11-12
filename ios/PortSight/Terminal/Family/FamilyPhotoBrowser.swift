//
//  FamilyPhotoBrowser.swift
//  PortSight
//
//  The 图库 photo grid and its full-screen viewer, following the PhotosTransition sample (Balaji Venkatesh):
//  a tapped tile grows from its place in the grid into a full-screen cover, pages left and right through the
//  library, and shrinks back to its (updated) tile on close or on dragging down. The viewer's top bar carries
//  the date and place; swiping up reveals the caption, people and place below the photo, as in Photos.
//

import SwiftUI
import MapKit
import PortSightKit

enum FamilyLibraryZoom: String, CaseIterable, Identifiable {
    case years = "年", months = "月", all = "全部"
    var id: String { rawValue }
}

// MARK: - Grid

private struct PhotoHeroConfig {
    /// The selected slot's id (FamilyLibrarySlot), which stays the same while its photo loads.
    var selected: String?
    var sourceRect: CGRect = .zero
    var showViewer = false
}

/// The library grid: oldest first, each tile opening the hero viewer. It lives inside the page's single
/// ScrollView (shared with the 年 / 月 cards, so the navigation bar keeps tracking one scroll view);
/// `position` is that scroll view's, so paging in the viewer keeps the current photo's tile in view.
struct FamilyHeroGrid: View {
    /// Every place in the library (FamilyLibrary), loaded or not: the grid has its full height from the start
    /// and each month's photos fill in as it comes into view.
    let slots: [FamilyLibrarySlot]
    @Binding var position: ScrollPosition
    var spacing: CGFloat = 3
    @State private var config = PhotoHeroConfig()

    var body: some View {
        let library = FamilyLibrary.shared
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3), spacing: spacing) {
            ForEach(slots) { slot in
                Rectangle()
                    .foregroundStyle(.clear)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let photo = library.photo(at: slot) {
                            GeometryReader {
                                let rect = $0.frame(in: .global)
                                let updatedRect: CGRect? = config.selected == slot.id ? rect : nil

                                FamilyPhotoTile(photo: photo, cornerRadius: 4)
                                    // The tile hides while the viewer shows it.
                                    .opacity(config.selected == slot.id ? 0 : 1)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(.rect)
                                    .accessibilityAddTraits(.isButton)
                                    .onTapGesture {
                                        config.selected = slot.id
                                        config.sourceRect = rect
                                        withoutAnimation { config.showViewer = true }
                                    }
                                    // Paging in the viewer moves the grid; keep the return target in sync.
                                    .onChange(of: updatedRect) { _, newValue in
                                        if let newValue { config.sourceRect = newValue }
                                    }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(.secondarySystemFill))
                                .task(id: slot.monthID) { await library.keepLoading(slot.monthID) }
                        }
                    }
                    .id(slot.id)
            }
        }
        .scrollTargetLayout()
        .fullScreenCover(isPresented: $config.showViewer) {
            config.selected = nil
        } content: {
            FamilyPhotoViewer(config: $config, slots: slots)
        }
        .onChange(of: config.selected) { oldValue, newValue in
            if let newValue, oldValue != nil {
                position.scrollTo(id: newValue)
            }
        }
    }
}

// MARK: - Viewer

private struct FamilyPhotoViewer: View {
    @Binding var config: PhotoHeroConfig
    let slots: [FamilyLibrarySlot]
    @State private var isExpanded = false
    @State private var viewSize: CGSize = .zero
    @State private var safeArea = EdgeInsets()
    /// Drag towards closing (downwards).
    @State private var dragOffset: CGSize = .zero
    /// Info panel: shown state plus the live vertical drag (negative = up).
    @State private var showInfo = false
    @State private var infoDrag: CGFloat = 0
    @State private var liked: Set<String> = []
    /// The place and photo last shown, so the viewer can follow a photo whose place changed.
    @State private var shown: (slot: String, photo: String)?
    /// While opening and closing, the photo is drawn by a plain overlay above the pager. Pages of a paging
    /// TabView are built lazily and on iOS 27 pick up the final state without animating, so growing out of
    /// (and shrinking back into) the tile happens on this layer; the pager takes over once it is open.
    @State private var heroActive = true

    var body: some View {
        // Drag and info-panel transforms sit on the pager itself, not inside its pages: pages are hosted
        // lazily and do not animate their own state changes on iOS 27, so springing back after a short
        // drag would snap. Everything else is an overlay, so the full-screen layers cannot resize the
        // view that `viewSize` measures (that feeds back into their own frames).
        TabView(selection: $config.selected) {
            ForEach(slots) { slot in
                page(slot)
                    .frame(width: viewSize.width, height: screenHeight)
                    .clipped()
                    .tag(Optional(slot.id))
                    .ignoresSafeArea()
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .modifier(ViewerTransform(scale: dragScale, offset: dragOffset, lift: currentLift))
        .opacity(heroActive ? 0 : 1)
        .overlay {
            if heroActive, let photo = current {
                let source = config.sourceRect
                photoCanvas(photo, expanded: isExpanded)
                    .frame(width: isExpanded ? viewSize.width : source.width,
                           height: isExpanded ? screenHeight : source.height)
                    .clipped()
                    .modifier(ViewerTransform(scale: dragScale, offset: dragOffset, lift: currentLift))
                    .offset(x: isExpanded ? 0 : source.minX, y: isExpanded ? 0 : source.minY)
                    // Top-leading like the pages (which start at the top of the screen), so the hand-off
                    // to the pager lands on the same spot instead of hopping up.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            chrome
                .compositingGroup()
                .opacity(interactiveOpacity)
                .opacity(isExpanded ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            if let photo = current {
                infoPanel(photo)
                    .frame(height: panelHeight, alignment: .top)
                    .offset(y: (1 - infoProgress) * (panelHeight + safeArea.bottom + 20))
                    .opacity(isExpanded ? 1 : 0)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        // The whole screen takes the vertical drags, the info panel included.
        .contentShape(.rect)
        .gesture(PanGesture(handle: handlePan))
        .presentationBackground {
            // White in light mode, black in dark mode.
            Rectangle().fill(Color(.systemBackground)).opacity(interactiveOpacity).opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { viewSize = $0 }
        .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { safeArea = $0 }
        .onChange(of: config.selected) { _, selected in
            infoDrag = 0
            prefetchNeighbours(of: selected)
        }
        .onChange(of: current?.id) { _, id in followPhoto(id) }
        .onChange(of: slots) { _, slots in keepSelection(in: slots) }
        .task {
            guard !isExpanded else { return }
            // Expand only once the cover knows its size; otherwise the photo would grow towards a zero
            // frame and then snap to full screen instead of growing out of its tile.
            while viewSize == .zero, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(4)) }
            // Hand over to the pager only once the spring has fully settled (.removed): at .logicallyComplete
            // (the default) it is still a few percent short of full screen, and the pager, drawn at the final
            // size, made the last bit of the growth jump instead of easing in.
            withAnimation(animation, completionCriteria: .removed) {
                isExpanded = true
            } completion: {
                heroActive = false
            }
        }
    }

    private var library: FamilyLibrary { FamilyLibrary.shared }

    /// The selected slot's photo (nil while its month loads).
    private var current: FamilyPhoto? { config.selected.flatMap(library.photo(slotID:)) }

    /// One page: the photo (with a play button for an Immich video), or a spinner while its month loads.
    @ViewBuilder private func page(_ slot: FamilyLibrarySlot) -> some View {
        if let photo = library.photo(at: slot) {
            photoCanvas(photo, expanded: true)
                .overlay {
                    if photo.isVideo, photo.remote != nil, !heroActive { FamilyRemoteVideo(photo: photo) }
                }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: slot.monthID) { await library.keepLoading(slot.monthID) }
        }
    }

    /// When a refresh changes a month under the open viewer, its photos move to other places: stay on the photo
    /// that was on screen rather than on its old place.
    private func followPhoto(_ id: String?) {
        guard let selected = config.selected, let id else { return }
        if let shown, shown.slot == selected, shown.photo != id, let slot = FamilyLibrarySlot(id: selected),
           let moved = library.slotID(ofPhoto: shown.photo, inMonth: slot.monthID), moved != selected {
            withoutAnimation { config.selected = moved }
            return
        }
        shown = (selected, id)
    }

    /// A month that turned out smaller can drop the selected place: move to that month's last photo.
    private func keepSelection(in slots: [FamilyLibrarySlot]) {
        guard let selected = config.selected, !slots.contains(where: { $0.id == selected }),
              let slot = FamilyLibrarySlot(id: selected) else { return }
        withoutAnimation { config.selected = slots.last(where: { $0.monthID == slot.monthID })?.id ?? slots.last?.id }
    }

    /// Paging towards the edge of a month starts loading the next one, so its photos are there on arrival.
    private func prefetchNeighbours(of slotID: String?) {
        guard let slotID, let index = slots.firstIndex(where: { $0.id == slotID }) else { return }
        for offset in [-12, 12] where slots.indices.contains(index + offset) {
            library.ensureLoaded(slots[index + offset].monthID)
        }
    }

    /// The photo, shown whole and centred on the screen (the canvas covers the full screen from its top
    /// edge). As the info panel comes in it slides up at full width, edge to edge, until its bottom sits
    /// just above the panel.
    private func photoCanvas(_ photo: FamilyPhoto, expanded: Bool) -> some View {
        FamilyPhotoTile(photo: photo, cornerRadius: 0, symbolFont: expanded ? .system(size: 64) : .title2,
                        square: false, fit: expanded)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentLift: CGFloat {
        guard isExpanded, let photo = current else { return 0 }
        return infoProgress * infoLift(photo)
    }

    /// Shrinks the photo as it is dragged down to close, like Photos.
    private var dragScale: CGFloat {
        let down = max(dragOffset.height, 0)
        return max(0.5, 1 - down / max(screenHeight, 1) * 0.9)
    }

    /// How far the photo moves up with the info panel fully shown: its bottom ends 10 pt above the panel.
    private func infoLift(_ photo: FamilyPhoto) -> CGFloat {
        let height = min(viewSize.width / max(photo.displayAspectRatio, 0.01), screenHeight)
        let centre = screenHeight / 2
        let target = screenHeight - panelHeight - 10 - height / 2
        return min(0, target - centre)
    }

    private var screenHeight: CGFloat { viewSize.height + safeArea.top + safeArea.bottom }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "chevron.left").font(.title3).frame(width: 20, height: 30)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("返回")

                Spacer(minLength: 0)

                Menu {
                    Button("复制", systemImage: "doc.on.doc") {}
                    Button("加入相册", systemImage: "rectangle.stack.badge.plus") {}
                    Button("隐藏", systemImage: "eye.slash") {}
                } label: {
                    Image(systemName: "ellipsis").font(.title3).frame(width: 20, height: 30)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("更多")
            }
            .overlay {
                if let photo = current {
                    VStack(spacing: 1) {
                        Text(photo.estimatedEra ?? photo.dateText(.dateTime.year().month().day()))
                            .font(.callout.weight(.semibold))
                        Text(subtitle(photo)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: photo)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 64)
                }
            }

            Spacer(minLength: 0)

            HStack {
                shareButton

                HStack(spacing: 2) {
                    Button {
                        guard let id = current?.id else { return }
                        if liked.contains(id) { liked.remove(id) } else { liked.insert(id) }
                    } label: {
                        Image(systemName: liked.contains(current?.id ?? "") ? "suit.heart.fill" : "suit.heart")
                            .font(.title3).padding(.horizontal, 8).padding(.vertical, 10)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .sensoryFeedback(.selection, trigger: liked)
                    .accessibilityLabel("喜欢")
                    .accessibilityAddTraits(liked.contains(current?.id ?? "") ? .isSelected : [])
                    Button {
                        withAnimation(animation) { showInfo.toggle() }
                    } label: {
                        Image(systemName: showInfo ? "info.circle.fill" : "info.circle").font(.title3)
                            .padding(.horizontal, 8).padding(.vertical, 10)
                    }
                    .accessibilityLabel("信息")
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 6)
                .glassEffect(.regular.interactive(), in: .capsule)
                .frame(maxWidth: .infinity)

                Button {} label: {
                    Image(systemName: "trash").font(.title3).frame(width: 20, height: 30)
                }
                .buttonStyle(.glass)
                .disabled(true)
                .accessibilityLabel("删除")
            }
            .opacity(1 - infoProgress)
        }
        .padding(.horizontal, 15)
    }

    /// Shares the caption for the demo library; for an Immich photo its picture (fetched when shared). Videos
    /// are not shared from here.
    @ViewBuilder private var shareButton: some View {
        let icon = Image(systemName: "square.and.arrow.up.fill").font(.title3).frame(width: 20, height: 30)
        if let photo = current, photo.remote != nil {
            if photo.isVideo {
                Button {} label: { icon }
                    .buttonStyle(.glass)
                    .disabled(true)
                    .accessibilityLabel("分享")
            } else {
                ShareLink(item: FamilySharedPhoto(id: photo.id),
                          preview: SharePreview(photo.dateText(.dateTime.year().month().day()))) { icon }
                    .buttonStyle(.glass)
                    .accessibilityLabel("分享")
            }
        } else if let photo = current {
            ShareLink(item: photo.caption) { icon }
                .buttonStyle(.glass)
                .accessibilityLabel("分享")
        } else {
            // Still loading: nothing to share yet.
            Button {} label: { icon }
                .buttonStyle(.glass)
                .disabled(true)
                .accessibilityLabel("分享")
        }
    }

    private func subtitle(_ photo: FamilyPhoto) -> String {
        var parts: [String] = []
        if photo.estimatedEra == nil { parts.append(photo.dateText(.dateTime.weekday(.abbreviated).hour().minute())) }
        if let place = DemoFamilyData.place(photo.placeID) { parts.append(place.name) }
        if let city = photo.remote?.city { parts.append(city) }
        return parts.isEmpty ? "扫描的老照片" : parts.joined(separator: " · ")
    }

    // MARK: Info panel (swipe up)

    private func infoPanel(_ photo: FamilyPhoto) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(.secondary).frame(width: 36, height: 5).frame(maxWidth: .infinity)

            if !photo.caption.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("照片描述").font(.headline)
                        Spacer()
                        FamilyModelBadge()
                    }
                    Text(photo.caption).font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let remote = photo.remote {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("拍摄时间", value: photo.dateText(.dateTime.year().month().day().hour().minute()))
                    if let city = remote.city { LabeledContent("拍摄地", value: city) }
                    if photo.isVideo, let ms = remote.durationMs {
                        LabeledContent("时长", value: Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond)))
                    }
                }
                .font(.subheadline)
            }

            if !photo.peopleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("照片里的人").font(.headline)
                    HStack(spacing: 14) {
                        ForEach(photo.peopleIDs.compactMap(DemoFamilyData.person)) { person in
                            VStack(spacing: 5) {
                                FamilyPersonAvatar(person: person, size: 44)
                                Text(person.name).font(.caption)
                            }
                        }
                    }
                }
            }

            if let place = DemoFamilyData.place(photo.placeID) {
                let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 4_000, longitudinalMeters: 4_000)),
                    interactionModes: []) {
                    Marker(place.name, coordinate: coordinate)
                }
                .id(photo.id)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label(place.name, systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, safeArea.bottom + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
    }

    // MARK: Gestures and state

    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        switch gesture.state {
        case .began, .changed:
            if showInfo {
                infoDrag = max(0, translation.y)
            } else if translation.y >= 0 {
                dragOffset = CGSize(width: translation.x, height: translation.y)
                infoDrag = 0
            } else {
                dragOffset = .zero
                infoDrag = translation.y
            }
        default:
            if !showInfo && dragOffset.height > 50 {
                dismiss()
            } else {
                withAnimation(animation.speed(1.2)) {
                    if showInfo && infoDrag > 60 { showInfo = false }
                    if !showInfo && infoDrag < -50 { showInfo = true }
                    infoDrag = 0
                    dragOffset = .zero
                }
            }
        }
    }

    private func dismiss() {
        heroActive = true
        Task {
            // Close once the photo has fully landed on its tile (not after a fixed delay, which could cut the
            // spring's tail short and make the tile jump into place).
            withAnimation(animation.speed(1.2), completionCriteria: .removed) {
                dragOffset = .zero
                infoDrag = 0
                showInfo = false
                isExpanded = false
            } completion: {
                withoutAnimation { config.showViewer = false }
            }
        }
    }

    private var animation: Animation { .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: 0) }

    /// Measured from the bottom edge of the screen.
    private var panelHeight: CGFloat { min(max(screenHeight * 0.46, 320), 440) }

    /// 0 = photo only, 1 = info panel fully up; follows the finger while dragging.
    private var infoProgress: CGFloat {
        guard panelHeight > 0 else { return 0 }
        return min(max((showInfo ? 1 : 0) - infoDrag / panelHeight, 0), 1)
    }

    /// Fades the background and chrome while dragging down to close.
    private var interactiveOpacity: CGFloat {
        let fade = max(dragOffset.height, 0) / max(viewSize.height * 0.3, 1)
        return isExpanded ? 1 - fade : 0
    }
}

// MARK: - Helpers (from the sample)

private struct PanGesture: UIGestureRecognizerRepresentable {
    var handle: (UIPanGestureRecognizer) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer()
        gesture.minimumNumberOfTouches = 1
        gesture.maximumNumberOfTouches = 1
        gesture.delegate = context.coordinator
        return gesture
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        handle(recognizer)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                return scrollView.contentOffset.y <= 0
            }
            return false
        }

        /// Vertical drags only (down closes, up shows info); horizontal ones page between photos.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}

/// Drag (follows the finger, shrinking as it goes down) and the lift for the info panel.
private struct ViewerTransform: ViewModifier {
    let scale: CGFloat
    let offset: CGSize
    let lift: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .offset(y: lift)
    }
}

private func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

// MARK: - 年 / 月 cards

/// One card per month (or year), oldest at the top like the grid; tapping zooms in.
struct FamilyLibraryCards: View {
    struct Group: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        /// The photo on the card: the group's middle one.
        let cover: FamilyLibrarySlot?
        /// Where tapping goes: the year's first month, or the month's first photo.
        let target: String?
    }

    let groups: [Group]
    let tall: Bool
    let open: (Group) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(groups) { group in
                Button { open(group) } label: { card(group) }
                    .buttonStyle(.plain)
                    .id(group.id)
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func card(_ group: Group) -> some View {
        let library = FamilyLibrary.shared
        return ZStack {
            if let cover = group.cover.flatMap(library.photo(at:)) {
                FamilyPhotoTile(photo: cover, cornerRadius: 0, symbolFont: .system(size: 44), square: false)
                    .accessibilityHidden(true)
            } else {
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .task(id: group.cover?.monthID) { if let cover = group.cover { await library.keepLoading(cover.monthID) } }
            }
        }
            .frame(height: tall ? 260 : 190)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title).font(tall ? .largeTitle.bold() : .title2.bold())
                    Text(group.subtitle).font(.subheadline.weight(.medium)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// One card per month, as the library counts them (Immich's months follow where each photo was taken).
    static func months(of library: FamilyLibrary) -> [Group] {
        library.months.map { month in
            Group(id: month.id, title: month.title,
                  subtitle: places(library.loaded[month.id] ?? []) ?? "\(month.count) 项",
                  cover: FamilyLibrarySlot(monthID: month.id, index: month.count / 2),
                  target: FamilyLibrarySlot(monthID: month.id, index: 0).id)
        }
    }

    static func years(of library: FamilyLibrary) -> [Group] {
        var years: [(year: Int, months: [FamilyLibraryMonth])] = []
        for month in library.months {
            if years.last?.year == month.year { years[years.count - 1].months.append(month) }
            else { years.append((month.year, [month])) }
        }
        return years.map { year, months in
            let total = months.reduce(0) { $0 + $1.count }
            // The year's middle photo.
            var remaining = total / 2
            var cover: FamilyLibrarySlot?
            for month in months {
                if remaining < month.count { cover = FamilyLibrarySlot(monthID: month.id, index: remaining); break }
                remaining -= month.count
            }
            return Group(id: "\(year)", title: "\(year)", subtitle: "\(total) 项", cover: cover, target: months.first?.id)
        }
    }

    private static func places(_ photos: [FamilyPhoto]) -> String? {
        var names: [String] = []
        for photo in photos {
            guard let name = DemoFamilyData.place(photo.placeID)?.name ?? photo.remote?.city else { continue }
            if !names.contains(name) { names.append(name) }
            if names.count == 2 { break }
        }
        return names.isEmpty ? nil : names.joined(separator: "、")
    }
}
