import SwiftUI

/// Buat Workspace (K32): a short wizard in the style of Tambah dompet. Name, icon and colour, the starting
/// categories, the payday cycle; nothing is saved until the last step. Inviting people comes later (stage 3).
struct CreateWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared

    /// The server said the free plan is full (K29): the Plus offer opens over Beranda once this closes.
    let onLimit: () -> Void

    private enum Step: Int, CaseIterable { case start, name, look, categories, payday, warning, done }
    /// K38: how the new Workspace begins. `convert` turns Workspace Pribadi itself into it, with its history.
    private enum Start { case empty, convert, moveAll }

    @State private var step: Step = .start
    @State private var start: Start = .empty
    @State private var movedCount: Int?
    @State private var moveFailed = false
    @State private var forward = true
    @State private var name = ""
    @State private var icon: String?
    @State private var color: String
    @State private var showsAllIcons = false
    @State private var copiesCategories = false
    @State private var paydayDay: Int?
    @State private var isSaving = false
    @State private var failed = false
    @State private var created: Workspace?
    @State private var opensAtLaunch = false
    @State private var bump = false
    @State private var showsInvite = false
    @FocusState private var nameFocused: Bool

    private static let nameLimit = 40
    /// Converting keeps categories and start of period of Workspace Pribadi, so those two questions are skipped.
    private var questionSteps: [Step] { start == .convert ? [.start, .name, .look, .warning] : [.start, .name, .look, .categories, .payday] }

    init(onLimit: @escaping () -> Void) {
        self.onLimit = onLimit
        // K32: the colour is chosen for the person; the first one no workspace of theirs uses yet
        let used = Set(WorkspaceStore.shared.shared.compactMap(\.color))
        _color = State(initialValue: WalletIcon.presetColors.first { !used.contains($0.name) }?.name ?? "hijau")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDone: Bool { step == .done }
    private var stepIndex: Int { isDone ? questionSteps.count : questionSteps.firstIndex(of: step) ?? 0 }

    private var isValid: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .look: icon != nil
        default: true
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                progress.padding(.top, 4)
                ScrollView {
                    content
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                            removal: .opacity.combined(with: .offset(x: forward ? -24 : 24))))
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .foregroundStyle(Color.appText)
        .animation(.settle(0.42), value: step)
        .onChange(of: step) { _, value in nameFocused = value == .name }
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $showsInvite) { if let created { InviteSheet(workspace: created) } }
        .alert(L("Workspace belum bisa dibuat"), isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("Koneksi terputus atau ada yang berubah. Coba lagi sebentar."))
        }
    }

    // MARK: Chrome (same as Tambah dompet)

    private var topBar: some View {
        ZStack {
            HStack {
                ZStack(alignment: .leading) {
                    Button(L("Batal")) { dismiss() }
                        .font(.app(17))
                        .foregroundStyle(Color.appPrimary)
                        .opacity(step == .start ? 1 : 0)
                        .allowsHitTesting(step == .start)
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(L("Kembali"))
                    .opacity(step != .start && !isDone ? 1 : 0)
                    .allowsHitTesting(step != .start && !isDone && !isSaving)
                }
                Spacer()
                Text("\(stepIndex + 1)/\(questionSteps.count)")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .opacity(isDone ? 0 : 1)
            }
            .padding(.horizontal, 20)

            Text(title)
                .font(.app(17, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 60)
        }
        .frame(height: 44)
    }

    private var title: String {
        switch step {
        case .start: L("Buat Workspace")
        case .name: L("Nama Workspace")
        case .look: L("Ikon dan warna")
        case .categories: L("Kategori awal")
        case .payday: L("Awal periode")
        case .warning: L("Sebelum lanjut")
        case .done: L("Selesai")
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<questionSteps.count, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appDivider)
                        Capsule().fill(Color.appPrimary).frame(width: i <= stepIndex ? geo.size.width : 0)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 24)
        .opacity(isDone ? 0 : 1)
        .animation(.settle(0.48), value: stepIndex)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .start: startStep
        case .name: nameStep
        case .warning: warningStep
        case .look: lookStep
        case .categories: categoriesStep
        case .payday: paydayStep
        case .done: doneStep
        }
    }

    private var preview: some View {
        WorkspaceBadge(icon: icon, color: color, size: 72)
            .scaleEffect(bump ? 1.1 : 1)
            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.38), value: bump)
            .animation(.easeInOut(duration: 0.24), value: color)
            .frame(maxWidth: .infinity)
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Mau mulai dengan apa?"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Pilih bagaimana Workspace baru ini dimulai."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            VStack(spacing: 0) {
                choiceRow(L("Mulai kosong"), L("Workspace baru tanpa dompet dan catatan."), on: start == .empty) { start = .empty }
                choiceRow(L("Ubah Workspace Pribadi saya"), L("Semua dompet dan riwayat ikut jadi milik Workspace ini."), on: start == .convert) { start = .convert }
                choiceRow(L("Pindahkan semua dompet"), L("Dompet ikut pindah dengan saldo terakhir, tanpa riwayat."), on: start == .moveAll) { start = .moveAll }
            }
            .padding(.top, 12)
        }
    }

    private var warningStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Seluruh riwayat akan terlihat anggota"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Workspace Pribadi-mu berubah jadi %@. Semua dompet, catatan, budget, dan kategori di dalamnya bisa dilihat siapa pun yang kamu undang, termasuk catatan lama.", trimmedName))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            Text(L("Kamu langsung dapat Workspace Pribadi baru yang kosong. Perubahan ini tidak bisa dikembalikan."))
                .font(.app(15, weight: .semibold)).foregroundStyle(Color.appText).lineSpacing(2)
                .padding(.top, 14)
        }
    }

    private var nameStep: some View {
        VStack(spacing: 10) {
            preview
            TextField("", text: $name, prompt: Text(L("Nama Workspace")).foregroundStyle(Color.appTextTertiary))
                .font(.app(26, weight: .bold))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .tint(.appPrimary)
                .submitLabel(.next)
                .focused($nameFocused)
                .frame(height: 36)
                .onChange(of: name) { _, value in if value.count > Self.nameLimit { name = String(value.prefix(Self.nameLimit)) } }
                .onSubmit { if isValid { next() } }
            Text(L("Contoh: Rumah, Liburan Bali, Usaha"))
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .frame(height: 20)
        }
    }

    private var lookStep: some View {
        VStack(spacing: 10) {
            preview
            Text(trimmedName)
                .font(.app(26, weight: .bold)).tracking(-0.3)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: 36)
            VStack(spacing: 4) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 4) {
                    ForEach(CategoryCatalog.visibleIcons(expanded: showsAllIcons), id: \.self) { symbol in
                        let isOn = symbol == icon
                        Button { pick { icon = symbol } } label: {
                            Circle()
                                .fill(isOn ? WorkspaceStyle.color(color).opacity(0.14) : .clear)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: symbol)
                                        .font(.system(size: 21))
                                        .foregroundStyle(isOn ? WorkspaceStyle.color(color) : Color.appTextSecondary)
                                }
                                .animation(.easeInOut(duration: 0.18), value: isOn)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                Button(showsAllIcons ? L("Lebih sedikit") : L("Lihat semua ikon")) {
                    withAnimation(.settle(0.36)) { showsAllIcons.toggle() }
                }
                .font(.app(13, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
                .frame(maxWidth: .infinity, minHeight: 36)
                Rectangle().fill(Color.appDivider).frame(height: 1).padding(.horizontal, 10)
                HStack(spacing: 0) {
                    ForEach(WalletIcon.presetColors, id: \.name) { preset in
                        let isOn = preset.name == color
                        Button { pick { color = preset.name } } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 24, height: 24)
                                .padding(3)
                                .overlay { Circle().stroke(preset.color, lineWidth: 2).opacity(isOn ? 1 : 0) }
                                .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.36), value: isOn)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Warna %@", preset.name))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
        }
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Mulai dari mana?"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Kategori di Workspace ini berdiri sendiri. Mengubahnya tidak memengaruhi Workspace lain."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            VStack(spacing: 0) {
                choiceRow(L("Kategori bawaan Saku"), L("Daftar standar, tanpa kategori buatanmu."), on: !copiesCategories) { copiesCategories = false }
                choiceRow(L("Salin dari Workspace Pribadi"), L("Kategori buatanmu ikut disalin."), on: copiesCategories) { copiesCategories = true }
            }
            .padding(.top, 12)
        }
    }

    private func choiceRow(_ title: String, _ subtitle: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
                    .opacity(on ? 1 : 0)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var paydayStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Awal periode Workspace ini"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Periode budget dan ringkasan mulai di tanggal ini. Boleh dikosongkan, Pemilik bisa mengaturnya nanti."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            PaydayDayPicker(selection: $paydayDay)
                .padding(.horizontal, -24)
                .padding(.top, 12)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 6) {
            WorkspaceBadge(icon: icon, color: color, size: 96).padding(.top, 24).padding(.bottom, 10)
            Text(L("Workspace dibuat")).font(.app(22, weight: .semibold)).tracking(-0.3)
            Text(doneMessage)
                .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
            if store.shared.count == 1 {
                Toggle(isOn: $opensAtLaunch) {
                    Text(L("Buka Workspace ini saat app dijalankan"))
                        .font(.app(16)).foregroundStyle(Color.appText)
                }
                .tint(Color.appPrimary)
                .frame(minHeight: 48)
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var doneMessage: String {
        if start == .convert { return L("Workspace Pribadi-mu sekarang jadi %@. Workspace Pribadi baru yang kosong sudah menunggumu.", trimmedName) }
        if moveFailed { return L("%@ sudah dibuat, tapi dompet belum bisa dipindah karena batas dompet gratis. Tidak ada yang berubah di dompetmu.", trimmedName) }
        if let movedCount { return L("%@ sudah ada di daftar Workspace-mu. %lld dompet ikut pindah.", trimmedName, movedCount) }
        return L("%@ sudah ada di daftar Workspace-mu.", trimmedName)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            if isDone {
                // the PRD asks the next screen to offer inviting right away
                primaryButton(L("Undang anggota")) { showsInvite = true }
                Button { finish(open: true) } label: {
                    Text(L("Buka Workspace"))
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color.appFill, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                Button(L("Tetap di sini")) { finish(open: false) }
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(height: 36)
            } else {
                primaryButton(step == questionSteps.last ? (start == .convert ? L("Ubah Workspace Pribadi") : L("Buat Workspace")) : L("Lanjut"), enabled: isValid) { next() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.appBackground)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isSaving { ProgressView().tint(.white) }
                else { Text(title).font(.app(17, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(enabled ? Color.appPrimary : Color(light: 0xC7C7CC, dark: 0x48484A), in: Capsule())
            .animation(.easeInOut(duration: 0.26), value: enabled)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled || isSaving)
    }

    // MARK: Actions

    private func pick(_ change: () -> Void) {
        change()
        bump = true
        Task { try? await Task.sleep(for: .milliseconds(180)); bump = false }
    }

    private func back() {
        guard let at = questionSteps.firstIndex(of: step), at > 0 else { return }
        forward = false
        step = questionSteps[at - 1]
    }

    private func next() {
        guard let at = questionSteps.firstIndex(of: step) else { return }
        if at == questionSteps.count - 1 { Task { await save() }; return }
        forward = true
        step = questionSteps[at + 1]
    }

    private func save() async {
        guard let icon, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if start == .convert {
                created = try await store.convertPersonal(name: trimmedName, icon: icon, color: color)
            } else {
                created = try await store.create(name: trimmedName, icon: icon, color: color, copyCategories: copiesCategories, paydayDay: paydayDay)
                if start == .moveAll, let created {
                    do { movedCount = try await store.moveAllWallets(to: created) } catch { moveFailed = true }
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            forward = true
            step = .done
        } catch let error as WorkspaceError {
            switch error {
            case .limit: dismiss(); onLimit()
            case .guest: dismiss()
            case .ownerDeleting, .ownerMustTransfer, .walletLimit, .notMovable, .readOnly, .other: failed = true
            }
        } catch { failed = true }
    }

    private func finish(open: Bool) {
        guard let created else { dismiss(); return }
        Task {
            if opensAtLaunch { try? await store.setDefault(created) }
            dismiss()
            if open { try? await Task.sleep(for: .milliseconds(350)); store.open(created) }
        }
    }
}
