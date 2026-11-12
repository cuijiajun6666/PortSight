//
//  VaultView.swift
//  PortSight
//
//  文件保险箱: family documents (ID papers, insurance, property, medical). Opening it needs Face ID or the
//  vault's own 6-digit passcode; after 5 minutes away (VaultSession) it asks again, and its contents are
//  blurred in the app switcher. Demo documents only.
//

import SwiftUI
import LocalAuthentication
import PortSightKit

struct VaultView: View {
    var body: some View {
        NavigationStack { VaultEmbeddedView() }
    }
}

/// The vault itself, inside whichever NavigationStack shows it (its own tab, or pushed from 更多).
/// Both share `VaultSession.shared`, so unlocking in one place opens the other too.
struct VaultEmbeddedView: View {
    @Environment(\.scenePhase) private var scenePhase
    private var session = VaultSession.shared

    var body: some View {
        ZStack {
            if session.isUnlocked {
                VaultHomeView(lock: { session.lock() }).transition(.blurReplace)
            } else {
                VaultGateView(onUnlock: { session.unlock() }).transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.3), value: session.isUnlocked)
        // Hide the contents from the app switcher (but not behind the Face ID sheet, which also makes the
        // app inactive); after 5 minutes away it asks again.
        .blur(radius: session.isUnlocked && scenePhase != .active && !session.isAuthenticating ? 24 : 0)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: session.appWentToBackground()
            case .active:
                session.isAuthenticating = false
                session.appBecameActive()
            default: break
            }
        }
        .vaultPresence()
    }
}

extension View {
    /// Counts this screen as "inside the vault" for the grace period.
    func vaultPresence() -> some View {
        onAppear { VaultSession.shared.appeared() }
            .onDisappear { VaultSession.shared.disappeared() }
    }
}

// MARK: - Lock screen

struct VaultGateView: View {
    enum Stage { case unlock, create, confirm(String) }

    var onUnlock: () -> Void
    @State private var stage: Stage = VaultPasscode.isSet ? .unlock : .create
    @State private var code = ""
    @State private var message: String?
    @State private var failures = 0
    @State private var lockedUntil: Date?
    @State private var shake = 0
    @FocusState private var focused: Bool

    private var biometryName: String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    private var title: String {
        switch stage {
        case .unlock: "文件保险箱"
        case .create: "设置保险箱密码"
        case .confirm: "再输入一次"
        }
    }

    private var subtitle: String {
        switch stage {
        case .unlock: biometryName.map { "用\($0)或输入 6 位密码打开" } ?? "输入 6 位密码打开"
        case .create: "这是保险箱自己的密码，和手机锁屏密码分开"
        case .confirm: "确认刚才的 6 位密码"
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: shake)
            VStack(spacing: 8) {
                Text(title).font(.title2.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            dots
                .modifier(Shake(animatableData: CGFloat(shake)))
                .onTapGesture { focused = true }
            // Invisible field drives the number pad; the dots above show progress.
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(VaultPasscode.length))
                    if code.count == VaultPasscode.length { submit() }
                }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.red).transition(.opacity)
            }
            if case .unlock = stage, let biometryName {
                Button { authenticateWithBiometrics() } label: {
                    Label("使用\(biometryName)", systemImage: biometryName == "面容 ID" ? "faceid" : "touchid")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            Spacer()
            Text("文件存放在家里的主机上，只通过私有网络访问。")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // Tapping anywhere outside the dots puts the keyboard away.
        .onTapGesture { focused = false }
        .portSightHeader("保险箱", caption: VaultPasscode.isSet ? "已上锁" : "第一次使用，先设一个密码")
        .toolbar {
            if focused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { focused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                        .accessibilityLabel("收起键盘")
                }
            }
        }
        .sensoryFeedback(.error, trigger: shake)
        .onAppear {
            // Not straight after the lock button: that lock screen waits for a tap on the Face ID button.
            if case .unlock = stage, biometryName != nil, !VaultSession.shared.lockedByHand {
                authenticateWithBiometrics()
            } else if !VaultSession.shared.lockedByHand {
                focused = true
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<VaultPasscode.length, id: \.self) { index in
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1.5)
                    .background(Circle().fill(index < code.count ? Color.primary : .clear))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("已输入 \(code.count) 位，共 \(VaultPasscode.length) 位")
    }

    private func submit() {
        let entered = code
        code = ""
        switch stage {
        case .create:
            stage = .confirm(entered)
            message = nil
        case .confirm(let first):
            if entered != first {
                stage = .create
                fail("两次输入不一致，请重新设置")
            } else if VaultPasscode.set(entered) {
                onUnlock()
            } else {
                stage = .create
                fail("密码没能存进钥匙串，请再试一次")
            }
        case .unlock:
            if let lockedUntil, lockedUntil > .now {
                fail("尝试次数过多，\(Int(lockedUntil.timeIntervalSinceNow.rounded(.up))) 秒后再试")
                return
            }
            if VaultPasscode.verify(entered) {
                failures = 0
                onUnlock()
            } else {
                failures += 1
                if failures >= VaultPasscode.maxAttempts {
                    failures = 0
                    lockedUntil = .now.addingTimeInterval(VaultPasscode.lockout)
                    fail("连续输错 \(VaultPasscode.maxAttempts) 次，请 \(Int(VaultPasscode.lockout)) 秒后再试")
                } else {
                    fail("密码不对，还可以试 \(VaultPasscode.maxAttempts - failures) 次")
                }
            }
        }
    }

    private func fail(_ text: String) {
        withAnimation(.default) { message = text; shake += 1 }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        context.localizedFallbackTitle = "输入保险箱密码"
        VaultSession.shared.isAuthenticating = true
        Task {
            do {
                if try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "打开文件保险箱") {
                    onUnlock()
                }
            } catch {
                focused = true
            }
        }
    }
}

/// Horizontal shake for a wrong passcode.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - Contents

struct VaultHomeView: View {
    var lock: () -> Void
    @State private var question = ""
    @State private var showChangePasscode = false

    var body: some View {
        List {
            if !DemoVaultData.expiringSoon.isEmpty {
                Section("快到期") {
                    ForEach(DemoVaultData.expiringSoon) { doc in
                        NavigationLink { VaultDocumentView(document: doc) } label: { VaultRow(document: doc) }
                    }
                }
            }

            Section {
                TextField("问一句：爸爸的护照什么时候到期？", text: $question)
                    .submitLabel(.search)
                if let answer = DemoVaultData.answer(question) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label("回答", systemImage: "sparkles").font(.subheadline.weight(.semibold)); Spacer(); FamilyModelBadge() }
                        Text(answer.answer).font(.subheadline)
                    }
                    .padding(.vertical, 4)
                    ForEach(answer.documentIDs.compactMap(DemoVaultData.document)) { doc in
                        NavigationLink { VaultDocumentView(document: doc) } label: { VaultRow(document: doc) }
                    }
                } else if question.isEmpty {
                    ForEach(DemoVaultData.questions, id: \.self) { item in
                        Button(item) { question = item }.font(.subheadline)
                    }
                }
            } header: {
                Text("问保险箱")
            } footer: {
                Text("扫描件里的文字由本地模型识别，只在家里的主机上处理。")
            }

            ForEach(VaultDocument.Category.allCases) { category in
                let docs = DemoVaultData.documents.filter { $0.category == category }
                if !docs.isEmpty {
                    Section {
                        ForEach(docs) { doc in
                            NavigationLink { VaultDocumentView(document: doc) } label: { VaultRow(document: doc) }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }

            Section {
                Button("修改保险箱密码") { showChangePasscode = true }
                Button("立即上锁", role: .destructive, action: lock)
            } footer: {
                Text("离开 App 5 分钟后会自动上锁。")
            }
        }
        .listStyle(.insetGrouped)
        .portSightHeader("保险箱", caption: "\(DemoVaultData.documents.count) 份文件 · 5 分钟内回来不用再验证")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: lock) { Image(systemName: "lock.fill") }.accessibilityLabel("上锁")
            }
        }
        .sheet(isPresented: $showChangePasscode) {
            NavigationStack {
                VaultGateView(onUnlock: { showChangePasscode = false })
                    .onAppear { VaultPasscode.clear() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { showChangePasscode = false } } }
            }
        }
    }
}

struct VaultRow: View {
    let document: VaultDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.category.icon)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text((DemoFamilyData.person(document.ownerID)?.name ?? "") + "的" + document.title).font(.subheadline.weight(.medium))
                Text("\(document.pages) 页 · " + document.addedAt.formatted(date: .abbreviated, time: .omitted) + " 加入")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let days = document.daysToExpiry() {
                Text(days < 0 ? "已过期" : days <= 90 ? "\(days) 天后到期" : "有效")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(days <= 30 ? .red : days <= 90 ? .orange : .secondary)
            }
        }
    }
}

struct VaultDocumentView: View {
    let document: VaultDocument
    @State private var revealed: Set<String> = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    private var session = VaultSession.shared

    init(document: VaultDocument) { self.document = document }

    var body: some View {
        List {
            Section {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)
                    .aspectRatio(1.58, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: document.category.icon).font(.largeTitle).foregroundStyle(.secondary)
                            Text("扫描件 · \(document.pages) 页").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(document.fields, id: \.label) { field in
                    LabeledContent(field.label) {
                        if field.sensitive && !revealed.contains(field.label) {
                            Button {
                                revealed.insert(field.label)
                            } label: {
                                Text(String(repeating: "•", count: min(field.value.count, 10))).monospaced()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("已隐藏，轻点显示")
                        } else {
                            Text(field.value).textSelection(.enabled)
                        }
                    }
                }
                if let expires = document.expires {
                    LabeledContent("到期", value: expires.formatted(date: .long, time: .omitted))
                }
            } header: {
                HStack { Text("识别出的信息"); Spacer(); FamilyModelBadge() }
            } footer: {
                Text("敏感号码默认隐藏，轻点显示。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle((DemoFamilyData.person(document.ownerID)?.name ?? "") + "的" + document.title)
        .navigationBarTitleDisplayMode(.inline)
        .blur(radius: session.isUnlocked && scenePhase == .active ? 0 : 24)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.appWentToBackground() }
            if phase == .active { session.appBecameActive() }
        }
        // Back to the lock screen when the grace period ran out while away.
        .onChange(of: session.isUnlocked) { _, open in if !open { dismiss() } }
        .vaultPresence()
    }
}
