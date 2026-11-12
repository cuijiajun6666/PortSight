import SwiftUI
import UniformTypeIdentifiers
import PortSightKit

private struct OpenPhotoUploaderKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Opens 云盘 · 上传 from anywhere in the main window (总览 and 照片 buttons).
    var openPhotoUploader: () -> Void {
        get { self[OpenPhotoUploaderKey.self] }
        set { self[OpenPhotoUploaderKey.self] = newValue }
    }
}

/// Drop photos or whole folders; they queue for Immich on the Mac mini and upload in the background.
struct DesktopPhotoUploadView: View {
    @ObservedObject var queue: PhotoUploadQueue
    @State private var isTargeted = false
    @State private var isImporting = false

    var body: some View {
        // A page on the content surface: the drop zone takes all spare height until files are queued,
        // then the list does, so everything follows the window size.
        VStack(alignment: .leading, spacing: 18) {
            DesktopPageHeader(eyebrow: "上传到 Immich", title: "上传照片",
                              detail: "拖入照片、视频或整个文件夹，Mac mini 上的 Immich 会在后台接收。")
            dropZone
            if !queue.items.isEmpty { summary; list }
            if let message = queue.message {
                Label(message, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .closesForPush($isImporting)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.image, .movie, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { queue.add(urls) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "photo.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted ? DesktopTheme.blue : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(isTargeted ? "松开即可加入上传队列" : "把照片、视频或整个文件夹拖到这里")
                .font(.system(size: 15, weight: .semibold))
            Text("文件夹里的照片和视频会被一起找出来，其他文件自动跳过。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Button("选择文件…") { isImporting = true }
                .buttonStyle(.glass)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 150, maxHeight: queue.items.isEmpty ? .infinity : 170)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? DesktopTheme.blue.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? DesktopTheme.blue : Color.primary.opacity(0.15),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .onDrop(of: [.fileURL, .image, .movie], isTargeted: $isTargeted) { providers in
            receive(providers)
            return true
        }
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .animation(.smooth(duration: 0.25), value: queue.items.isEmpty)
        .accessibilityIdentifier("photo_drop_zone")
    }

    /// Finder drags carry file URLs; the Photos app sends file promises, whose data is copied in first.
    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in queue.add([url]) }
                }
                continue
            }
            guard let type = [UTType.movie, .image].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
            let name = provider.suggestedName
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { temporary, _ in
                guard let temporary, let copy = PhotoUploadQueue.keepImportedCopy(of: temporary, suggestedName: name) else { return }
                Task { @MainActor in queue.add([copy]) }
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(queue.photoCount) 张照片 · \(queue.videoCount) 段视频")
                .font(.system(size: 15, weight: .semibold))
            Text(ByteCountFormatter.string(fromByteCount: queue.totalBytes, countStyle: .file))
                .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            if queue.skipped > 0 {
                Text("· 跳过 \(queue.skipped) 个非媒体文件").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("清空", role: .destructive) { queue.clear() }.buttonStyle(.link)
        }
    }

    private var list: some View {
        List {
            ForEach(queue.items) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isVideo ? "video" : "photo").foregroundStyle(.secondary).frame(width: 18)
                    Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    stateLabel(item.state)
                    Button { queue.remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                        .help("移出队列")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 120, maxHeight: .infinity)
    }

    @ViewBuilder private func stateLabel(_ state: UploadItem.State) -> some View {
        switch state {
        case .waiting: Text("等待上传").font(.system(size: 11)).foregroundStyle(.secondary)
        case .uploading(let progress): ProgressView(value: progress).frame(width: 60)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(DesktopTheme.green)
        case .failed(let reason): Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DesktopTheme.orange).help(reason)
        }
    }

    private var footer: some View {
        HStack {
            Label("切到其他页面或关闭窗口后，上传会继续在后台进行。", systemImage: "icloud.and.arrow.up")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button("开始上传") { queue.start() }
                .buttonStyle(.glassProminent)
                .disabled(queue.waitingCount == 0)
                .keyboardShortcut(.defaultAction)
        }
    }
}
