import SwiftUI

/// Buat Workspace (K32): a short wizard in the style of Tambah dompet. Name, icon and colour, the starting
/// categories, the payday cycle; nothing is saved until the last step. Inviting people comes later (stage 3).
struct CreateWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = WorkspaceStore.shared

    /// The server said the free plan is full (K29): the Plus offer opens over Beranda once this closes.
    let onLimit: () -> Void

    private enum Step: Int, CaseIterable { case intro, start, name, look, categories, payday, warning, done, fail, limit }
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
    @State private var nameError = false
    @State private var nameShake = 0
    @State private var holdShake = 0
    @Namespace private var colorNS
    @State private var created: Workspace?
    @State private var opensAtLaunch = false
    @State private var bump = false
    @State private var invite: WorkspaceInvite?
    @State private var inviteFailed = false
    @State private var codeCopied = false
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
    private var showsProgress: Bool { ![.done, .intro, .fail, .limit].contains(step) }
    private var stepIndex: Int { isDone ? questionSteps.count : questionSteps.firstIndex(of: step) ?? 0 }

    private var isValid: Bool {
        switch step {
        case .name: !trimmedName.isEmpty
        case .look: icon != nil || photo != nil
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
                    .opacity(showsProgress && step != .start ? 1 : 0)
                    .allowsHitTesting(showsProgress && step != .start && !isSaving)
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
        case .intro, .start: L("Workspace baru")
        case .name: L("Nama")
        case .look: L("Tampilan")
        case .categories: L("Kategori")
        case .payday: L("Periode")
        case .warning: L("Konfirmasi")
        case .done: L("Selesai")
        case .fail, .limit: ""
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
        case .fail: noticeStep(icon: "exclamationmark.triangle", tint: Color.appError, title: L("Workspace belum bisa dibuat"), text: L("Ada gangguan saat menyimpan. Datamu aman dan belum berubah. Coba lagi sebentar lagi."))
        case .limit: noticeStep(icon: "crown", tint: Color.appPrimary, title: L("Kuota Workspace gratis terpakai"), text: L("Akun gratis bisa membuat 1 Workspace. Dengan Plus kamu bisa membuat tanpa batas. Bergabung ke Workspace orang lain tetap tidak dibatasi."))
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

    /// The big left-aligned heading every step opens with.
    private func header(_ title: String, _ subtitle: String, size: CGFloat = 30) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.app(size, weight: .bold)).tracking(-0.3)
            Text(subtitle).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoNote(_ text: Text) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 17)).foregroundStyle(Color.appPrimary)
            text.font(.app(13)).foregroundStyle(Color.appTextSecondary).lineSpacing(2)
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(L("Apa itu Workspace?"), L("Ruang bersama untuk mencatat uang dengan orang terdekat."))
                .opacity(introShown ? 1 : 0).offset(y: introShown ? 0 : 12)
                .animation(.settle(0.3), value: introShown)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(introPoints.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(width: 40, height: 40)
                            .background(Color.appPrimary.opacity(0.12), in: Circle())
                            .scaleEffect(introShown ? 1 : 0.9)
                            .animation(.easeOut(duration: 0.25).delay(0.06 * Double(index) + 0.06), value: introShown)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.app(16, weight: .semibold))
                            Text(point.text).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(1)
                        }
                    }
                    .opacity(introShown ? 1 : 0)
                    .offset(y: introShown ? 0 : 12)
                    .animation(.settle(0.3).delay(0.06 * Double(index) + 0.06), value: introShown)
                }
            }
            VStack(spacing: 0) {
                Button {
                    withAnimation(.settle(0.32)) { rulesOpen.toggle() }
                } label: {
                    HStack {
                        Text(L("Aturan singkat")).font(.app(15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.appTextSecondary)
                            .rotationEffect(.degrees(rulesOpen ? 180 : 0))
                    }
                    .foregroundStyle(Color.appText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if rulesOpen {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(introRules, id: \.self) { rule in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Color.appPrimary).frame(width: 5, height: 5).padding(.top, 7)
                                Text(rule).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 14)
                    .transition(.opacity)
                }
            }
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(introShown ? 1 : 0).offset(y: introShown ? 0 : 12)
            .animation(.settle(0.3).delay(0.3), value: introShown)
            infoNote(Text(L("Akun gratis bisa membuat 1 Workspace.") + " ") + Text("Plus").fontWeight(.semibold).foregroundColor(Color.appText) + Text(" " + L("tanpa batas.")))
                .opacity(introShown ? 1 : 0).offset(y: introShown ? 0 : 12)
                .animation(.settle(0.3).delay(0.36), value: introShown)
        }
        .onAppear { withAnimation { introShown = true } }
    }

    private var startStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("Mau mulai dengan apa?"), L("Kamu bisa mengundang anggota setelah Workspace dibuat."))
            VStack(spacing: 12) {
                choiceCard(L("Mulai kosong"), L("Workspace baru tanpa dompet. Tambahkan sendiri nanti."), icon: "plus.circle", on: start == .empty, weight: .primary) { start = .empty }
                choiceCard(L("Ubah Workspace Pribadi saya"), L("Semua dompet dan riwayat transaksi menjadi milik Workspace ini."), icon: "arrow.triangle.2.circlepath", on: start == .convert, weight: .outlined) { start = .convert }
                choiceCard(L("Pindahkan semua dompet"), L("Hanya saldo dompet yang dipindah, tanpa riwayat."), icon: "wallet.bifold", on: start == .moveAll, weight: .plain) { start = .moveAll }
            }
        }
    }

    // MARK: Badge

    private var initial: String { trimmedName.first.map { String($0).uppercased() } ?? "" }

    /// The wizard's rounded-square badge: colour, an initial or the chosen icon, or the picked photo.
    private func wizardBadge(size: CGFloat, showsInitial: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(WorkspaceStyle.color(color))
            if showsInitial {
                if initial.isEmpty {
                    Image(systemName: "person.2.fill").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.9))
                } else {
                    Text(initial).font(.app(size * 0.45, weight: .bold)).foregroundStyle(.white)
                }
            } else if let icon {
                Image(systemName: icon).font(.system(size: size * 0.47)).foregroundStyle(.white)
                    .id(icon).transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Image(systemName: "person.2.fill").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.9))
            }
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
        .scaleEffect(bump ? 1.09 : 1)
        .animation(.timingCurve(0.3, 1.6, 0.5, 1, duration: 0.38), value: bump)
        .animation(.easeOut(duration: 0.3), value: color)
        .animation(.easeOut(duration: 0.2), value: icon)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            wizardBadge(size: 76, showsInitial: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            header(L("Beri nama Workspace"), L("Contoh: Rumah, Liburan Bali, Usaha."), size: 28)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    TextField("", text: $name, prompt: Text(L("Nama Workspace")).foregroundStyle(Color.appTextTertiary))
                        .font(.app(17))
                        .tint(.appPrimary)
                        .submitLabel(.next)
                        .focused($nameFocused)
                        .frame(maxHeight: .infinity)
                        .onChange(of: name) { _, value in
                            if value.count > Self.nameLimit { name = String(value.prefix(Self.nameLimit)) }
                            if nameError && !trimmedName.isEmpty { withAnimation(.easeOut(duration: 0.2)) { nameError = false } }
                            if !value.isEmpty { bumpOnce() }
                        }
                        .onSubmit { next() }
                    Text("\(name.count)/\(Self.nameLimit)")
                        .font(.app(13)).monospacedDigit().foregroundStyle(Color.appTextSecondary)
                        .opacity(name.count >= 30 ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: name.count >= 30)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(nameError ? Color.appError : (nameFocused ? Color.appPrimary : .clear), lineWidth: 1.5))
                .modifier(ShakeEffect(shakes: CGFloat(nameShake)))
                if nameError {
                    Text(L("Nama Workspace wajib diisi.")).font(.app(13)).foregroundStyle(Color.appError)
                        .transition(.opacity)
                }
            }
        }
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            wizardBadge(size: 84, showsInitial: false)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            if lookMode == .photo {
                WorkspacePhotoPanel(imageUrl: nil, photo: $photo, removed: $photoRemoved)
                lookRow(icon: "square.grid.2x2", title: L("Pakai ikon"), subtitle: L("Pilih dari daftar ikon")) { lookMode = .icon }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Ikon")).font(.app(15, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(CategoryCatalog.visibleIcons(expanded: showsAllIcons), id: \.self) { symbol in
                            let isOn = symbol == icon
                            Button { pick { icon = symbol } } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 21))
                                    .foregroundStyle(isOn ? WorkspaceStyle.color(color) : Color.appTextSecondary)
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(isOn ? WorkspaceStyle.color(color).opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    .animation(.easeOut(duration: 0.2), value: isOn)
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    Button {
                        withAnimation(.settle(0.36)) { showsAllIcons.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsAllIcons ? L("Lebih sedikit") : L("Lihat semua ikon"))
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                .rotationEffect(.degrees(showsAllIcons ? 180 : 0))
                        }
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                        .frame(minHeight: 44)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Warna")).font(.app(15, weight: .semibold))
                    HStack(spacing: 0) {
                        ForEach(WalletIcon.presetColors, id: \.name) { preset in
                            let isOn = preset.name == color
                            Button { pick { color = preset.name } } label: {
                                ZStack {
                                    if isOn {
                                        Circle().strokeBorder(Color.appText, lineWidth: 2)
                                            .frame(width: 38, height: 38)
                                            .matchedGeometryEffect(id: "ring", in: colorNS)
                                    }
                                    Circle().fill(preset.color).frame(width: 28, height: 28)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: color)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Warna %@", preset.name))
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }
                lookRow(icon: "photo", title: L("Pakai foto"), subtitle: L("Opsional")) { lookMode = .photo }
            }
        }
    }

    private func lookRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
    }

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("Kategori awal"), L("Pilih titik awal untuk kategori Workspace ini."))
            VStack(spacing: 12) {
                choiceCard(L("Kategori bawaan Saku"), L("Mulai dengan daftar kategori standar."), icon: "square.grid.2x2", on: !copiesCategories, weight: .filled) { copiesCategories = false }
                choiceCard(L("Salin dari Workspace Pribadi"), L("Pakai kategori yang sudah kamu buat."), icon: "doc.on.doc", on: copiesCategories, weight: .filled) { copiesCategories = true }
            }
            infoNote(Text(L("Kategori tiap Workspace berdiri sendiri. Mengubahnya di sini tidak memengaruhi Workspace lain.")))
        }
    }

    private enum CardWeight { case primary, outlined, plain, filled }

    /// One option card: a leading icon, title and subtitle, and a check circle that draws in when chosen.
    private func choiceCard(_ title: String, _ subtitle: String, icon: String, on: Bool, weight: CardWeight, action: @escaping () -> Void) -> some View {
        let big = weight == .primary
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.settle(0.3)) { action() }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: big ? 26 : weight == .plain ? 21 : 23))
                    .foregroundStyle(on && weight != .filled ? Color.appPrimary : Color.appTextSecondary)
                    .frame(width: 30)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.app(weight == .filled ? 17 : big ? 18 : 16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(subtitle).font(.app(14)).foregroundStyle(Color.appTextSecondary).lineSpacing(1)
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
            .padding(.vertical, big ? 20 : weight == .plain ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(weight == .primary || weight == .filled ? Color.appFill : .clear, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Color.appPrimary : (weight == .outlined ? Color.appBorder : .clear), lineWidth: 1.5))
            .opacity(on ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var paydayStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("Awal periode"), L("Tanggal gajian atau awal bulan anggaranmu. Opsional, Pemilik bisa mengaturnya nanti."))
            PaydayDayPicker(selection: $paydayDay)
                .padding(.horizontal, -24)
        }
    }

    private var warningStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(L("Sebelum lanjut"), L("Workspace Pribadi kamu akan diubah menjadi Workspace bersama."))
            VStack(alignment: .leading, spacing: 14) {
                warnRow("eye", L("Seluruh riwayat terlihat"), L("oleh anggota yang kamu undang."))
                warnRow("arrow.uturn.backward", L("Tidak bisa dibatalkan."), L("Setelah dibuat, Workspace tidak bisa dikembalikan menjadi pribadi."))
                warnRow("person", L("Kamu mendapat Workspace Pribadi baru"), L("yang masih kosong."))
            }
            holdToConfirm
        }
    }

    private func warnRow(_ icon: String, _ bold: String, _ rest: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 26)
            (Text(bold).fontWeight(.semibold) + Text(" " + rest).foregroundColor(Color.appTextSecondary))
                .font(.app(15)).lineSpacing(2)
        }
    }

    /// Hold 1.2 s to confirm an irreversible conversion; releasing early drains it back.
    private var holdToConfirm: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color.appFill)
                GeometryReader { geo in
                    Rectangle().fill(Color.appPrimary)
                        .frame(width: geo.size.width * (holdConfirmed ? 1 : holdProgress))
                }
                .clipShape(RoundedRectangle(cornerRadius: 28))
                RoundedRectangle(cornerRadius: 28).strokeBorder(holdConfirmed ? Color.appPrimary : Color.appBorder, lineWidth: 1.5)
                HStack(spacing: 8) {
                    Image(systemName: holdConfirmed ? "checkmark" : "hand.tap").font(.system(size: 15, weight: .bold))
                    Text(holdConfirmed ? L("Dikonfirmasi") : L("Tahan untuk konfirmasi"))
                }
                .font(.app(16, weight: .semibold))
                .foregroundStyle(holdConfirmed || holdProgress > 0.55 ? Color.white : Color.appText)
            }
            .frame(height: 56)
            .contentShape(Rectangle())
            .modifier(ShakeEffect(shakes: CGFloat(holdShake)))
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

    /// Failure and free-limit screens: a round icon, a heading, and one paragraph.
    private func noticeStep(icon: String, tint: Color, title: String, text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(tint)
                .frame(width: 88, height: 88)
                .background(tint.opacity(0.12), in: Circle())
                .modifier(ShakeEffect(shakes: CGFloat(nameShake)))
                .padding(.top, 60)
            Text(title).font(.app(26, weight: .bold)).multilineTextAlignment(.center)
            Text(text).font(.app(15)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center).lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.linear(duration: 0.28)) { nameShake += 1 } }
    }

    private var doneStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                wizardBadge(size: 72, showsInitial: false)
                    .scaleEffect(donePop ? 1 : 0.6).opacity(donePop ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: donePop)
                    .onAppear { donePop = true }
                Text(L("Workspace dibuat")).font(.app(26, weight: .bold)).padding(.top, 6)
                Text(doneMessage)
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center).lineSpacing(2)
            }
            .padding(.top, 24)
            inviteTicket.padding(.top, 28)
            if store.shared.count == 1 {
                Toggle(isOn: $opensAtLaunch) {
                    Text(L("Buka Workspace ini saat app dijalankan")).font(.app(15)).foregroundStyle(Color.appText)
                }
                .tint(Color.appPrimary)
                .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The live invitation code as a ticket: code on top, Salin and Bagikan below a dashed tear line.
    private var inviteTicket: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(L("Undang anggota dengan kode")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Group {
                    if let invite {
                        Text(InviteCode.grouped(invite.code))
                            .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(2)
                            .foregroundStyle(Color.appText).minimumScaleFactor(0.7).lineLimit(1)
                            .textSelection(.enabled)
                    } else if inviteFailed {
                        Button(L("Muat ulang kode")) { Task { await loadInvite() } }
                            .font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 44)
                Text(invite?.expiryDate.map { L("Berlaku sampai %@", Self.expiryFormat.string(from: $0)) } ?? " ")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20).padding(.bottom, 8)
            HStack(spacing: 0) {
                ticketAction(codeCopied ? L("Tersalin") : L("Salin"), icon: codeCopied ? "checkmark" : "doc.on.doc") { copyCode() }
                if let invite {
                    ShareLink(item: shareText(invite)) { ticketLabel(L("Bagikan"), icon: "square.and.arrow.up") }
                        .buttonStyle(RowPressStyle())
                } else {
                    ticketLabel(L("Bagikan"), icon: "square.and.arrow.up").opacity(0.4)
                }
            }
        }
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task { await loadInvite() }
    }

    private func ticketLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16))
            Text(title).font(.app(15, weight: .semibold))
        }
        .foregroundStyle(Color.appText)
        .frame(maxWidth: .infinity).frame(height: 52)
        .contentShape(Rectangle())
    }

    private func ticketAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { ticketLabel(title, icon: icon) }
            .buttonStyle(RowPressStyle())
            .disabled(invite == nil)
            .opacity(invite == nil ? 0.4 : 1)
    }

    private func copyCode() {
        guard let invite else { return }
        UIPasteboard.general.string = InviteCode.grouped(invite.code)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.2)) { codeCopied = true }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { codeCopied = false } }
    }

    private func shareText(_ invite: WorkspaceInvite) -> String {
        let until = invite.expiryDate.map { Self.expiryFormat.string(from: $0) } ?? ""
        return L("Gabung ke Workspace %@ di Saku. Kode undangan: %@. Berlaku sampai %@.", trimmedName, InviteCode.grouped(invite.code), until)
    }

    private static let expiryFormat: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .long; f.timeStyle = .none; f.locale = Locale.current; return f
    }()

    private func loadInvite() async {
        guard let created, invite == nil else { return }
        inviteFailed = false
        do { invite = try await store.invite(for: created) } catch { inviteFailed = true }
    }

    private var doneMessage: String {
        if start == .convert { return L("Workspace Pribadi-mu sekarang jadi %@. Workspace Pribadi baru yang kosong sudah menunggumu.", trimmedName) }
        if moveFailed { return L("%@ sudah dibuat, tapi dompet belum bisa dipindah karena batas dompet gratis. Tidak ada yang berubah di dompetmu.", trimmedName) }
        if let movedCount { return L("%@ sudah ada di daftar Workspace-mu. %lld dompet ikut pindah.", trimmedName, movedCount) }
        return L("%@ sudah ada di daftar Workspace-mu.", trimmedName)
    }

    // MARK: Buttons

    /// The shared button group (Docs/DesignSystem): a text button 1 : the pill 3.
    private var buttons: some View {
        Group {
            switch step {
            case .done:
                SmartSheetFooter(primary: L("Buka Workspace"), onPrimary: { finish(open: true) })
            case .intro:
                SmartSheetFooter(primary: L("Mulai"), secondary: L("Batal"), onPrimary: { next() }, onSecondary: { dismiss() })
            case .payday:
                SmartSheetFooter(primary: L("Tambah workspace"), isBusy: isSaving, secondary: L("Atur nanti"),
                                 onPrimary: { next() }, onSecondary: { paydayDay = nil; next() })
            case .fail:
                SmartSheetFooter(primary: L("Coba lagi"), isBusy: isSaving, secondary: L("Tutup"),
                                 onPrimary: { Task { await save() } }, onSecondary: { dismiss() })
            case .limit:
                SmartSheetFooter(primary: L("Lihat Plus"), secondary: L("Tidak sekarang"),
                                 onPrimary: { dismiss(); onLimit() }, onSecondary: { dismiss() })
            default:
                SmartSheetFooter(primary: step == questionSteps.last ? (start == .convert ? L("Ubah Workspace Pribadi") : L("Tambah workspace")) : L("Lanjut"),
                                 isBusy: isSaving, onPrimary: { next() })
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.appBackground)
    }

    // MARK: Actions

    private func pick(_ change: () -> Void) {
        change()
        bump = true
        Task { try? await Task.sleep(for: .milliseconds(180)); bump = false }
    }

    private func bumpOnce() {
        guard !bump else { return }
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
        if step == .name && trimmedName.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) { nameError = true }
            withAnimation(.linear(duration: 0.28)) { nameShake += 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        if step == .warning && !holdConfirmed {
            withAnimation(.linear(duration: 0.28)) { holdShake += 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        if step == .look && lookMode == .photo && photo == nil {
            withAnimation(.linear(duration: 0.28)) { holdShake += 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard let at = questionSteps.firstIndex(of: step) else { return }
        if at == questionSteps.count - 1 { Task { await save() }; return }
        forward = true
        step = questionSteps[at + 1]
        if step == .look, lookMode == .icon, icon == nil, photo == nil { icon = CategoryCatalog.visibleIcons(expanded: false).first }
    }

    private func save() async {
        guard !isSaving else { return }
        guard icon != nil || photo != nil else { forward = true; step = .fail; return }
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
            case .limit: forward = true; step = .limit
            case .guest: dismiss()
            case .ownerDeleting, .ownerMustTransfer, .walletLimit, .notMovable, .readOnly, .mapInvalid, .other: forward = true; step = .fail
            }
        } catch { forward = true; step = .fail }
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


