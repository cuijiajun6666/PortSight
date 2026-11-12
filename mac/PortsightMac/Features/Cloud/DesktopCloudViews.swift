import SwiftUI
import PortSightKit

/// 云盘 · 照片: the Immich library on the Mac mini.
struct DesktopCloudPhotosView: View {
    @Environment(\.openPhotoUploader) private var openUploader
    @EnvironmentObject private var uploads: PhotoUploadQueue
    private let library = DemoTerminalData.cloud
    @ObservedObject private var store = ServerStore.shared

    var body: some View {
        DesktopFullPage {
            DesktopPageHeader(eyebrow: "Immich 照片库",
                              title: library.photos.formatted() + " 张照片",
                              detail: library.videos.formatted() + " 段视频 · " + TerminalFormat.gigabytes(library.librarySizeGB)
                                + " · 最近上传 " + TerminalFormat.relative(library.lastUpload)) {
                HStack(spacing: 10) {
                    Button { openUploader() } label: {
                        Label(uploads.items.isEmpty ? "上传照片" : "上传照片（\(uploads.waitingCount)）", systemImage: "photo.badge.plus")
                    }
                    Button {} label: { Label("打开 Immich", systemImage: "arrow.up.forward.app") }
                        .disabled(true)
                        .help("Mac mini 到位并填写 Immich 地址后可用")
                }
                .buttonStyle(.glass).controlSize(.large)
            }

            // Same rule as 需要处理: only a photos disk the host reports as unmounted.
            if store.volumes != nil, (store.host?.disks?["photos"] ?? nil)?.mounted == false {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(DesktopTheme.orange)
                    Text("照片盘未挂载").font(.system(size: 13, weight: .semibold))
                    Text("新上传的照片会暂存在内置盘，挂载后再迁移。").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(DesktopTheme.orange.opacity(0.08), in: Capsule())
            }

            DesktopPageSection(title: "相簿", subtitle: "Immich 相簿") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: 18)], spacing: 22) {
                    ForEach(library.albums) { album in
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.quaternary)
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay {
                                    Image(systemName: album.symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                                }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(album.name).font(.system(size: 13, weight: .semibold))
                                Text(album.count.formatted() + " 项 · " + TerminalFormat.relative(album.updated))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// 云盘 · 存储: the four volumes from /host and what the photo library uses.
struct DesktopStorageView: View {
    @ObservedObject private var store = ServerStore.shared
    /// The /host disks, as on the 服务器 page (the sample until paired); empty while there are none.
    private var volumes: [StorageVolume] { store.volumes ?? [] }

    var body: some View {
        let mounted = volumes.filter(\.mounted)
        let free = mounted.reduce(0) { $0 + $1.freeGB }
        let backup = volumes.first { $0.key == "backup" }
        DesktopFullPage {
            DesktopPageHeader(eyebrow: "Mac mini 存储", title: volumes.isEmpty ? "暂无数据" : TerminalFormat.gigabytes(free) + " 可用",
                              detail: volumes.isEmpty ? "还没读到磁盘数据"
                                : "\(mounted.count) / \(volumes.count) 块盘已挂载 · " + (store.isSample ? "样例数据" : "来自 Mac mini 的磁盘数据"))
            VStack(alignment: .leading, spacing: 28) {
                if volumes.isEmpty {
                    DesktopPendingLabel(text: "暂无磁盘数据")
                } else {
                    ForEach(volumes) { DesktopVolumeRow(volume: $0) }
                }
            }
            DesktopPageSection(title: "照片库占用") {
                HStack(spacing: 28) {
                    DesktopStat(label: "照片库", value: TerminalFormat.gigabytes(DemoTerminalData.cloud.librarySizeGB))
                    DesktopStat(label: "待上传", value: "\(DemoTerminalData.cloud.pendingUploads)")
                    DesktopStat(label: "备份", value: backup.map { $0.mounted ? "已连接" : "未挂载" } ?? "—",
                                tint: backup.map { $0.mounted ? Color.primary : DesktopTheme.orange } ?? .secondary)
                }
            }
        }
    }
}

/// 云盘 · 文件传输: how to move files to the Mac mini; nothing here opens a connection.
struct DesktopTransferView: View {
    private let steps: [(icon: String, title: String, detail: String)] = [
        ("network", "连上 Tailscale", "本机和 Mac mini 都登录同一个 tailnet，不需要公网端口。"),
        ("folder.badge.plus", "在访达连接服务器", "访达 → 前往 → 连接服务器，输入 smb://" + TerminalPlaceholders.host),
        ("externaldrive", "放进主盘", "大文件放三星 T7 的「传输」文件夹，照片交给 Immich 上传。"),
        ("checkmark.seal", "确认已同步", "完成后在「存储」里看可用空间是否变化。"),
    ]

    var body: some View {
        DesktopFullPage(maxWidth: 820) {
            DesktopPageHeader(eyebrow: "文件传输", title: "通过 Tailscale 私网传文件", detail: "Mac mini 到位后再填写地址。")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Divider().opacity(0.5).padding(.leading, 52) }
                    HStack(alignment: .top, spacing: 18) {
                        Image(systemName: step.icon).font(.system(size: 18)).foregroundStyle(DesktopTheme.blue).frame(width: 34, height: 34)
                            .background(DesktopTheme.blue.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(index + 1). " + step.title).font(.system(size: 14, weight: .semibold))
                            Text(step.detail).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }
}
