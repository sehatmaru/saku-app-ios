import SwiftUI

/// Buat Workspace (K32): a short wizard in the style of Tambah dompet. Name, icon and colour, the starting
/// categories, the payday cycle; nothing is saved until the last step. Inviting people comes later (stage 3).
struct CreateWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared

    /// The server said the free plan is full (K29): the Plus offer opens over Beranda once this closes.
    let onLimit: () -> Void

    private enum Step: Int, CaseIterable { case intro, start, name, look, categories, payday, warning, done }
    /// K38: how the new Workspace begins. `convert` turns Workspace Pribadi itself into it, with its history.
    private enum Start { case empty, convert, moveAll }

    @State private var step: Step = .intro
    @State private var start: Start = .empty
    @State private var movedCount: Int?
    @State private var moveFailed = false
    @State private var forward = true
    @State private var name = ""
    @State private var icon: String?
    @State private var photo: UIImage?
    @State private var photoRemoved = false
    @State private var lookMode = WorkspaceLookMode.icon
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
    @State private var rulesOpen = false
    @State private var introShown = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdConfirmed = false
    @State private var donePop = false
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
    private var showsProgress: Bool { !isDone && step != .intro }
    private var stepIndex: Int { isDone ? questionSteps.count : questionSteps.firstIndex(of: step) ?? 0 }

    private var isValid: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .look: icon != nil || photo != nil
        case .warning: holdConfirmed
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
                        .opacity(step == .start || step == .intro ? 1 : 0)
                        .allowsHitTesting(step == .start || step == .intro)
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(L("Kembali"))
                    .opacity(step != .start && step != .intro && !isDone ? 1 : 0)
                    .allowsHitTesting(step != .start && step != .intro && !isDone && !isSaving)
                }
                Spacer()
                Text("\(stepIndex + 1)/\(questionSteps.count)")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                    .opacity(showsProgress ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: showsProgress)
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
        case .intro, .start: L("Tambah workspace")
        case .name: L("Nama Workspace")
        case .look: L("Ikon, warna, dan foto")
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
        .opacity(showsProgress ? 1 : 0)
        .animation(.settle(0.48), value: stepIndex)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch step {
        case .intro: introStep
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
        WorkspaceBadge(icon: icon, color: color, size: 72, image: photo)
            .scaleEffect(bump ? 1.1 : 1)
            .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.38), value: bump)
            .animation(.easeInOut(duration: 0.24), value: color)
            .frame(maxWidth: .infinity)
    }

    private struct IntroPoint { let icon: String; let title: String; let text: String }

    private var introPoints: [IntroPoint] { [
        IntroPoint(icon: "wallet.bifold", title: L("Uang bersama, satu tempat"), text: L("Dompet, catatan, dan budget dipakai bersama anggota.")),
        IntroPoint(icon: "lock", title: L("Keuanganmu tetap pribadi"), text: L("Workspace Pribadi tidak terlihat anggota lain.")),
        IntroPoint(icon: "person.3", title: L("Maksimal 5 anggota"), text: L("Termasuk kamu sebagai Pemilik.")),
        IntroPoint(icon: "crown", title: L("Kamu yang mengatur"), text: L("Hanya Pemilik yang mengundang, mengeluarkan anggota, mengatur kategori, budget, dan menghapus Workspace.")),
    ] }

    private var introRules: [String] { [
        L("Semua anggota boleh menambah, mengubah, dan menghapus catatan. Kategori dan budget hanya diatur Pemilik."),
        L("Akun gratis bisa membuat 1 Workspace; Plus tanpa batas. Bergabung ke Workspace orang lain tidak dibatasi."),
        L("Anggota yang keluar: catatannya tetap di Workspace, ditandai \"Mantan anggota\"."),
        L("Menghapus Workspace punya masa tunggu 7 hari sebelum data hilang permanen."),
    ] }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Apa itu Workspace?"))
                .font(.app(28, weight: .bold)).tracking(-0.4)
            Text(L("Ruang bersama untuk mencatat uang dengan orang terdekat."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(introPoints.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(width: 40, height: 40)
                            .background(Color.appPrimary.opacity(0.12), in: Circle())
                            .scaleEffect(introShown ? 1 : 0.9)
                            .animation(.easeOut(duration: 0.25).delay(0.06 * Double(index)), value: introShown)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.app(16, weight: .semibold))
                            Text(point.text).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                        }
                    }
                    .opacity(introShown ? 1 : 0)
                    .offset(y: introShown ? 0 : 12)
                    .animation(.settle(0.3).delay(0.06 * Double(index)), value: introShown)
                }
            }
            .padding(.top, 24)

            Button {
                withAnimation(.settle(0.32)) { rulesOpen.toggle() }
            } label: {
                HStack {
                    Text(L("Aturan singkat")).font(.app(15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(rulesOpen ? 180 : 0))
                }
                .foregroundStyle(Color.appText)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .accessibilityAddTraits(.isButton)
            Rectangle().fill(Color.appDivider).frame(height: 1)
            if rulesOpen {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(introRules, id: \.self) { rule in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Color.appTextTertiary).frame(width: 5, height: 5)
                            Text(rule).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                        }
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(Color.appTextSecondary)
                Text(L("Akun gratis bisa membuat 1 Workspace. Plus tanpa batas."))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
            }
            .padding(.top, 16)
        }
        .onAppear { withAnimation { introShown = true } }
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Mau mulai dengan apa?"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Pilih bagaimana Workspace baru ini dimulai."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            VStack(spacing: 10) {
                choiceCard(L("Mulai kosong"), L("Workspace baru tanpa dompet dan catatan."), icon: "plus.circle", on: start == .empty, weight: .primary) { start = .empty }
                choiceCard(L("Ubah Workspace Pribadi saya"), L("Semua dompet dan riwayat ikut jadi milik Workspace ini."), icon: "arrow.triangle.2.circlepath", on: start == .convert, weight: .outlined, tag: L("Tidak bisa dibatalkan")) { start = .convert }
                choiceCard(L("Pindahkan semua dompet"), L("Dompet ikut pindah dengan saldo terakhir, tanpa riwayat."), icon: "wallet.bifold", on: start == .moveAll, weight: .plain) { start = .moveAll }
            }
            .padding(.top, 16)
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
            holdToConfirm.padding(.top, 24)
        }
    }

    /// Hold 1.2 s to confirm an irreversible conversion; releasing early drains it back.
    private var holdToConfirm: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 26).fill(Color.appFill)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 26).fill(Color.appPrimary)
                        .frame(width: geo.size.width * (holdConfirmed ? 1 : holdProgress))
                }
                .clipShape(RoundedRectangle(cornerRadius: 26))
                RoundedRectangle(cornerRadius: 26).strokeBorder(holdConfirmed ? Color.appPrimary : Color.appBorder, lineWidth: 1.5)
                HStack(spacing: 8) {
                    Image(systemName: holdConfirmed ? "checkmark" : "hand.tap")
                    Text(holdConfirmed ? L("Dikonfirmasi") : L("Tahan untuk konfirmasi"))
                }
                .font(.app(16, weight: .semibold))
                .foregroundStyle(holdConfirmed || holdProgress > 0.55 ? Color.white : Color.appText)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 60, perform: {
                guard !holdConfirmed else { return }
                holdConfirmed = true
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }, onPressingChanged: { pressing in
                guard !holdConfirmed else { return }
                withAnimation(pressing ? .linear(duration: 1.2) : .settle(0.3)) { holdProgress = pressing ? 1 : 0 }
            })
            .accessibilityLabel(L("Tahan untuk konfirmasi"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { holdConfirmed = true }
            Text(holdConfirmed ? L("Siap dibuat.") : L("Tahan 1,2 detik. Lepas untuk membatalkan."))
                .font(.app(13)).foregroundStyle(Color.appTextSecondary)
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
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Text("\(name.count)/\(Self.nameLimit)").monospacedDigit()
                        .opacity(name.count >= 30 ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: name.count >= 30)
                }
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
            WorkspaceLookModePicker(mode: $lookMode)
            if lookMode == .photo {
                WorkspacePhotoPanel(imageUrl: nil, photo: $photo, removed: $photoRemoved)
            } else {
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
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Mulai dari mana?"))
                .font(.app(22, weight: .bold)).tracking(-0.3)
            Text(L("Kategori di Workspace ini berdiri sendiri. Mengubahnya tidak memengaruhi Workspace lain."))
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
                .padding(.top, 6)
            VStack(spacing: 0) {
                choiceCard(L("Kategori bawaan Saku"), L("Daftar standar, tanpa kategori buatanmu."), icon: "square.grid.2x2", on: !copiesCategories, weight: .outlined) { copiesCategories = false }
                choiceCard(L("Salin dari Workspace Pribadi"), L("Kategori buatanmu ikut disalin."), icon: "doc.on.doc", on: copiesCategories, weight: .outlined) { copiesCategories = true }
            }
            .padding(.top, 16)
        }
    }

    private enum CardWeight { case primary, outlined, plain }

    /// One option card: a leading icon, title and subtitle, and a check circle that draws in when chosen.
    private func choiceCard(_ title: String, _ subtitle: String, icon: String, on: Bool, weight: CardWeight, tag: String? = nil, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.settle(0.3)) { action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: weight == .primary ? 26 : 22))
                    .foregroundStyle(on ? Color.appPrimary : Color.appTextSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(weight == .primary ? 18 : 16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(1)
                    if let tag {
                        Label(tag, systemImage: "lock")
                            .font(.app(12, weight: .semibold))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(on ? Color.appPrimary : .clear)
                    Circle().strokeBorder(on ? Color.appPrimary : Color.appBorder, lineWidth: 1.5)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
                }
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, weight == .primary ? 20 : weight == .outlined ? 16 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(weight == .primary ? Color.appFill : .clear, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Color.appPrimary : (weight == .outlined ? Color.appBorder : .clear), lineWidth: 1.5))
            .opacity(on ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
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
            ZStack {
                Circle().stroke(WorkspaceStyle.color(color), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(donePop ? 1.6 : 1).opacity(donePop ? 0 : 0.35)
                    .animation(.easeOut(duration: 0.9).delay(0.15), value: donePop)
                WorkspaceBadge(icon: icon, color: color, size: 96, image: photo)
                    .scaleEffect(donePop ? 1 : 0.6).opacity(donePop ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6), value: donePop)
            }
            .padding(.top, 24).padding(.bottom, 10)
            .onAppear { donePop = true }
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
        VStack(spacing: 4) {
            if isDone {
                // the PRD asks the next screen to offer inviting right away
                HStack(spacing: 12) {
                    secondaryButton(L("Buka Workspace")) { finish(open: true) }
                    primaryButton(L("Undang anggota")) { showsInvite = true }
                }
                Button(L("Tetap di sini")) { finish(open: false) }
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(height: 40)
            } else if step == .intro {
                HStack(spacing: 12) {
                    secondaryButton(L("Batal")) { dismiss() }
                    primaryButton(L("Mulai")) { next() }
                }
            } else if step == .payday {
                HStack(spacing: 12) {
                    secondaryButton(L("Atur nanti")) { paydayDay = nil; next() }
                    primaryButton(L("Tambah workspace")) { next() }
                }
            } else {
                primaryButton(step == questionSteps.last ? (start == .convert ? L("Ubah Workspace Pribadi") : L("Tambah workspace")) : L("Lanjut"), enabled: isValid) { next() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.appBackground)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Color.appFill, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isSaving)
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isSaving { ProgressView().tint(.white) }
                else { Text(title).font(.app(17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8) }
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
        if step == .intro { forward = true; step = .start; return }
        guard let at = questionSteps.firstIndex(of: step) else { return }
        if at == questionSteps.count - 1 { Task { await save() }; return }
        forward = true
        step = questionSteps[at + 1]
    }

    private func save() async {
        guard icon != nil || photo != nil, !isSaving else { return }
        let icon = icon ?? "person.2.fill"
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
            // the picture needs the new workspace's id, so it goes up after creating; a failure here leaves the icon
            if let photo, let created, let jpeg = ProfileViewModel.avatarJPEG(photo) {
                try? await store.setImage(of: created, jpeg: jpeg)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            forward = true
            step = .done
        } catch let error as WorkspaceError {
            switch error {
            case .limit: dismiss(); onLimit()
            case .guest: dismiss()
            case .ownerDeleting, .ownerMustTransfer, .walletLimit, .notMovable, .readOnly, .mapInvalid, .other: failed = true
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
