//
//  FamilyDriveSettingsView.swift
//  PortSight
//
//  设置 → 上传到 Google 云盘: paste the configuration the admin sends (kept only in this iPhone's keychain), pick
//  "我是谁", see the upload list, clear the configuration. No secret is ever shown again after saving.
//

import SwiftUI
import PortSightKit

/// Sections for FamilySettingsView's Form.
struct FamilyDriveUploadSection: View {
    private var uploader = DriveUploader.shared
    @State private var config: DriveConfig?
    @State private var member = ""
    @State private var confirmClear = false

    var body: some View {
        Section {
            LabeledContent("状态", value: config.map { "已配置 · \($0.members.count) 位家人\($0.immich == nil ? "" : " · 含照片库")" } ?? "未配置")
            if let config {
                Picker("我是谁", selection: $member) {
                    if member.isEmpty { Text("请选择").tag("") }
                    ForEach(config.members, id: \.self) { Text($0).tag($0) }
                }
            }
            NavigationLink("粘贴配置…") { FamilyDriveConfigView(onSaved: reload) }
            NavigationLink { FamilyDriveUploadsView() } label: {
                LabeledContent("上传记录", value: summary)
            }
            if let status = uploader.status {
                Label(status.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if config != nil {
                Button("清除配置", role: .destructive) { confirmClear = true }
                    .confirmationDialog("清除配置？", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("清除配置", role: .destructive) {
                            uploader.clearConfiguration()
                            // The photo library's key went with it: back to the demo, and its pictures leave the phone.
                            FamilyImageStore.shared.clear()
                            FamilyLibrary.shared.reload()
                            reload()
                        }
                    } message: {
                        Text("这台 iPhone 上的钥匙、未传完的文件和存下的照片库图片会被移除。已发送的记录保留，云盘、照片库和相册里的照片不受影响。")
                    }
            }
        } header: {
            Text("上传到 Google 云盘")
        } footer: {
            Text("只上传、不删除云盘和相册里的照片；家人在国内需要先打开翻墙。")
        }
        .onAppear(perform: reload)
        .onChange(of: member) { _, name in
            guard !name.isEmpty, name != DriveMember.current else { return }
            DriveMember.current = name
        }
    }

    private var summary: String {
        let open = uploader.jobs.filter { $0.state != .sent && $0.state != .failed }.count
        if open > 0 { return "\(open) 个正在上传" }
        let failed = uploader.jobs.filter { $0.state == .failed }.count
        if failed > 0 { return "\(failed) 个失败" }
        return "\(uploader.jobs.count) 个"
    }

    private func reload() {
        config = DriveConfig.load()
        member = DriveMember.folderID(in: config) != nil ? (DriveMember.current ?? "") : ""
    }
}

/// Paste the JSON configuration. Saved to the keychain only; the editor is emptied after saving.
struct FamilyDriveConfigView: View {
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 220)
            } footer: {
                Text("把管理员发来的整段配置粘贴到这里。只保存在这台 iPhone 的钥匙串里，保存后不再显示。")
            }
            if let error {
                Section {
                    Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            Section {
                Button("保存", action: save)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay {
            // Hide the pasted secrets from the app switcher and its saved snapshot.
            if scenePhase != .active {
                ZStack {
                    Color(.systemGroupedBackground)
                    Label("配置已隐藏", systemImage: "lock.fill").foregroundStyle(.secondary)
                }
                .ignoresSafeArea()
            }
        }
        .navigationTitle("粘贴配置")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { text = "" }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { text = "" }
        }
    }

    private func save() {
        let config: DriveConfig
        do {
            config = try DriveConfig.parse(text)
        } catch let failure as DriveConfigError {
            error = failure.message
            return
        } catch {
            self.error = DriveConfigError.notJSON.message
            return
        }
        let previousImmich = DriveConfig.load()?.immich
        guard config.save() else {
            error = "保存到钥匙串失败，请重试"
            return
        }
        text = ""
        error = nil
        if let current = DriveMember.current, config.folders[current] == nil { DriveMember.current = nil }
        if DriveMember.current == nil, config.members.count == 1 { DriveMember.current = config.members.first }
        DriveUploader.shared.configurationChanged()
        // A new or changed `immich` part switches the 图库 to that library (or back to the demo). A different
        // server or key (or none) also takes the old library's pictures off the phone.
        if previousImmich != config.immich {
            if previousImmich != nil { FamilyImageStore.shared.clear() }
            FamilyLibrary.shared.reload(discardingCache: true)
        } else {
            FamilyLibrary.shared.reload()
        }
        onSaved()
        dismiss()
    }
}

/// The upload queue, newest first. Nothing remote can be deleted from here.
struct FamilyDriveUploadsView: View {
    private var uploader = DriveUploader.shared
    @State private var refreshing = false
    @State private var note: String?

    var body: some View {
        List {
            if let note {
                Label(note, systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if jobs.isEmpty {
                ContentUnavailableView("还没有上传", systemImage: "icloud.and.arrow.up",
                                       description: Text("在照片页右上角选择照片和视频，就会按原图上传。"))
                    .listRowBackground(Color.clear)
            }
            ForEach(jobs) { job in
                FamilyDriveJobRow(job: job) { uploader.retry(job) }
                    .swipeActions {
                        if job.state == .failed {
                            Button("重试") { uploader.retry(job) }.tint(.blue)
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("上传记录")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(refreshing)
                .accessibilityLabel("刷新")
            }
        }
        .onAppear { uploader.resume() }
        .task(id: note) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { note = nil }
        }
    }

    /// Skips the current wait and tries again now, e.g. right after turning the VPN on.
    private func refresh() async {
        refreshing = true
        let result = await uploader.refreshNow()
        withAnimation { note = result }
        refreshing = false
    }

    private var jobs: [DriveUploadJob] { uploader.jobs.sorted { $0.createdAt > $1.createdAt } }
}

private struct FamilyDriveJobRow: View {
    let job: DriveUploadJob
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.fileName).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if job.state == .failed {
                    Button("重试", action: retry).buttonStyle(.borderless).font(.subheadline)
                }
            }
            Text("\(job.member) · \(stateText)")
                .font(.caption)
                .foregroundStyle(job.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            if job.state == .uploading {
                ProgressView(value: job.progress)
            }
        }
        .padding(.vertical, 2)
    }

    private var stateText: String {
        switch job.state {
        case .preparing: "准备中"
        case .waiting: job.message.map { "等待上传 · \($0)" } ?? "等待上传"
        case .uploading: "正在上传 \(Int((job.progress * 100).rounded()))%"
        case .sent: "已发送"
        case .failed: "失败：\(job.message ?? "未知原因")"
        }
    }
}
