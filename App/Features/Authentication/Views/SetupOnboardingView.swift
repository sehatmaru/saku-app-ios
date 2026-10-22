import SwiftUI

/// Setup for every new user: name, wallets, rough starting balances, categories, a first budget, how to record
/// (Smart Tracker and notifications), payday and, for real accounts, the Saku Plus trial offer (Enhancement 2).
/// Guests run it before their account exists (`onBack` returns to sign-in) and skip the Plus offer; Google/Apple
/// users run it right after signing up, with the name prefilled.
struct SetupOnboardingView: View {
    /// Where the saving of the setup stands: the steps, the wait, or a failure with a retry.
    private enum Phase { case steps, saving, failed }

    var initialName = ""
    /// Nil after sign-in: there's nothing to go back to.
    var onBack: (() -> Void)?
    /// Applies the setup; the view shows `authViewModel.errorMessage` if it fails.
    let onFinish: (OnboardingSetup) async -> Void

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var step = 1
    @State private var isForward = true
    @State private var name = ""
    /// Categories left selected; the built-in ones start all on.
    @State private var selectedCategories = Set(OnboardingCategory.all.map(\.key))
    @State private var payday: Int?
    /// Tiles rise in one after another when step 4 opens.
    @State private var categoriesEntered = false
    /// Picked wallet ids, oldest first; the last three sit on top of the pocket.
    @State private var picked: [String] = []
    @State private var amounts: [String: Double] = [:]
    @State private var focusedCard: String?
    @FocusState private var isNameFocused: Bool
    /// Referral code of a friend, real accounts only (Fitur 2 K6: guests take no part).
    @State private var referralCode = ""
    @State private var referralAccepted = false
    /// The code the "Cek" button found valid; typing anything else clears it.
    @State private var referralChecked: String?
    @State private var isTestingCode = false
    @State private var referralMessage: String?
    @State private var isCheckingCode = false
    /// Monthly budget per expense category, by key (step 5).
    @State private var budgets: [String: Double] = [:]
    @State private var focusedBudget: String?
    @State private var trackerOn = false
    @State private var memorySync = false
    @State private var notification: SetupNotificationState = .idle
    @State private var joinsPlus = false
    @State private var phase: Phase = .steps
    @State private var plusUnavailable = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pickedWallets: [GuestWallet] { picked.compactMap { id in GuestWallet.all.first { $0.id == id } } }
    /// Credit cards start at 0, so Saldo only lists the other wallets.
    private var balanceWallets: [GuestWallet] { pickedWallets.filter { $0.type != .credit } }
    private var total: Double { balanceWallets.reduce(0) { $0 + (amounts[$1.id] ?? 0) } }
    /// What the Free plan will actually create: the first picks up to its limits (5 money wallets, 1 investment).
    private var createdWallets: [GuestWallet] {
        var money = 0, investments = 0
        return pickedWallets.filter { w in
            if w.type == .investment { investments += 1; return investments <= FreeLimits.investmentWallets }
            money += 1
            return money <= FreeLimits.moneyWallets
        }
    }
    private var isOverFreeLimit: Bool { createdWallets.count < pickedWallets.count }

    private var isGuest: Bool { onBack != nil }
    private var stepCount: Int { isGuest ? 7 : 8 }
    private var budgetCategories: [OnboardingCategory] { OnboardingCategory.expense.filter { selectedCategories.contains($0.key) } }

    private var setup: OnboardingSetup {
        OnboardingSetup(
            name: trimmedName,
            wallets: createdWallets.map { .init(name: $0.name, type: $0.type, icon: $0.iconId, balance: $0.type == .credit ? 0 : amounts[$0.id] ?? 0) },
            hiddenCategoryKeys: Set(OnboardingCategory.all.map(\.key)).subtracting(selectedCategories),
            paydayDay: payday,
            budgets: budgets.filter { selectedCategories.contains($0.key) && $0.value > 0 },
            smartTrackerConsent: trackerOn,
            memorySync: trackerOn && memorySync && !isGuest,
            joinsPlus: joinsPlus && !isGuest
        )
    }

    private var selectedExpenseCount: Int { OnboardingCategory.expense.filter { selectedCategories.contains($0.key) }.count }
    private var selectedIncomeCount: Int { OnboardingCategory.income.filter { selectedCategories.contains($0.key) }.count }
    /// Recording needs at least one category of each kind to pick from.
    private var categoriesValid: Bool { selectedExpenseCount > 0 && selectedIncomeCount > 0 }
    private var categoryCTA: String {
        if selectedExpenseCount == 0 { return L("Pilih minimal 1 pengeluaran") }
        if selectedIncomeCount == 0 { return L("Pilih minimal 1 pemasukan") }
        return L("Lanjut · %lld dipilih", selectedExpenseCount + selectedIncomeCount)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar

                ZStack {
                    switch step {
                    case 1: nameStep
                    case 2: walletStep
                    case 3: balanceStep
                    case 4: categoryStep
                    case 5: SetupBudgetStep(categories: budgetCategories, amounts: $budgets, focused: $focusedBudget)
                    case 6: SetupTrackingStep(isGuest: isGuest, tracker: $trackerOn, memorySync: $memorySync, notification: $notification)
                    case 7: SetupPaydayStep(payday: $payday)
                    default: SetupPlusStep()
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: isForward ? 36 : -36)),
                    removal: .opacity.combined(with: .offset(x: isForward ? -24 : 24))
                ))
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()

                cta
            }
            .background(Color.appBackground)

            if phase == .saving { savingScreen.transition(.opacity).zIndex(2) }
            if phase == .failed { failedScreen.transition(.opacity).zIndex(3) }
        }
        .animation(.easeOut(duration: 0.2), value: phase)
        .onAppear {
            authViewModel.errorMessage = nil
            if name.isEmpty { name = initialName }
        }
        .alert(L("Saku Plus belum bisa dibeli. Kami kabari saat sudah dibuka."), isPresented: $plusUnavailable) {
            Button("OK", role: .cancel) {}
        }
    }

    private func move(to newStep: Int) {
        isForward = newStep > step
        isNameFocused = false
        focusedBudget = nil
        withAnimation(.settle(0.5)) { step = newStep }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                if step == 4, balanceWallets.isEmpty { move(to: 2) } else if step > 1 { move(to: step - 1) } else { onBack?() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.appPrimary)
                    .frame(width: 44, height: 44)
            }
            .opacity(step == 1 && onBack == nil ? 0 : 1)
            .disabled(step == 1 && onBack == nil)
            .accessibilityLabel("Kembali")

            HStack(spacing: 6) {
                ForEach(1...stepCount, id: \.self) { index in
                    Button { if index < step { move(to: index) } } label: {
                        Capsule()
                            .fill(index <= step ? Color.appPrimary : Color.appBorder.opacity(0.5))
                            .frame(width: index == step ? 26 : 8, height: 8)
                            .animation(.settle(0.45), value: step)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= step)
                    .accessibilityLabel(L("Langkah %lld", index))
                }
            }
            .frame(maxWidth: .infinity)

            Text("\(step)/\(stepCount)")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 12)
        }
        .frame(height: 44)
        .padding(.leading, 12)
        .padding(.trailing, 4)
    }

    private var cta: some View {
        VStack(spacing: 4) {
            switch step {
            case 1:
                PrimaryButton(title: L("Lanjut"), isLoading: isCheckingCode, isEnabled: !trimmedName.isEmpty) { continueFromName() }
            case 2:
                PrimaryButton(title: picked.isEmpty ? L("Pilih minimal 1") : L("Lanjut · %lld dipilih", picked.count),
                              isEnabled: !picked.isEmpty) { move(to: balanceWallets.isEmpty ? 4 : 3) }
            case 3:
                PrimaryButton(title: L("Lanjut")) { move(to: 4) }
            case 4:
                PrimaryButton(title: categoryCTA, isEnabled: categoriesValid) { move(to: 5) }
            case 5:
                PrimaryButton(title: L("Lanjut")) { move(to: 6) }
            case 6:
                PrimaryButton(title: L("Lanjut")) { move(to: 7) }
                skipButton
            case 7:
                if isGuest {
                    PrimaryButton(title: L("Mulai pakai Saku")) { finish() }
                } else {
                    PrimaryButton(title: L("Lanjut")) { move(to: 8) }
                }
                if !isGuest { skipButton }
            default:
                PrimaryButton(title: L("Coba 7 hari")) { joinPlus() }
                Button { finish() } label: {
                    Text("Nanti saja").font(.app(17, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            // Content scrolls under a short fade above the button.
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .bottom)
                .frame(height: 32)
                .offset(y: -32)
                .allowsHitTesting(false)
        }
    }

    /// Steps 6 to 8 are all optional: this saves the setup as it stands.
    private var skipButton: some View {
        Button { finish() } label: {
            Text("Lewati semua").font(.app(15, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity).frame(height: 40)
        }
    }

    private func joinPlus() {
        guard PlusStore.isInternalBuild else { plusUnavailable = true; return }
        finish(joiningPlus: true)
    }

    /// Saves everything; success replaces this view (the welcome screen takes over), failure shows the retry screen.
    private func finish(joiningPlus: Bool = false) {
        joinsPlus = joiningPlus
        authViewModel.errorMessage = nil
        phase = .saving
        Task {
            await onFinish(setup)
            if authViewModel.errorMessage != nil { phase = .failed }
        }
    }

    private var savingScreen: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    PulsingSegment(delay: Double(index) * 0.15)
                }
            }
            .frame(width: 120)
            Text("Menyimpan setup").font(.app(17)).foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private var failedScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            ShakingBadge()
                .padding(.bottom, 24)
            Text("Setup belum tersimpan")
                .font(.app(28, weight: .bold)).tracking(-0.3)
                .rise(true, y: 16, delay: 0)
            Text("Koneksi terputus. Jawabanmu masih ada di iPhone ini, jadi tidak perlu mengisi ulang.")
                .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineSpacing(3)
                .padding(.top, 10)
                .rise(true, y: 16, delay: 0.08)
            Spacer()
            PrimaryButton(title: L("Coba lagi")) { finish(joiningPlus: joinsPlus) }
            Button {
                authViewModel.errorMessage = nil
                phase = .steps
            } label: {
                Text("Kembali ke setup").font(.app(15, weight: .medium)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private func heading(_ title: String, _ subtitle: String?, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: size == 34 ? 12 : 10) {
            Text(title)
                .font(.app(size, weight: .bold))
                .tracking(0.2)
                .foregroundStyle(Color.appText)
            if let subtitle {
                Text(subtitle)
                    .font(.app(size == 34 ? 17 : 16))
                    .lineSpacing(2.6)
                    .foregroundStyle(Color.appTextSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    // MARK: - 1 · Name

    private var referralState: SetupCodeState {
        if referralAccepted || referralChecked != nil { return .ok }
        return referralMessage != nil ? .bad : .idle
    }

    private var nameStep: some View {
        SetupNameStep(name: $name, referralCode: $referralCode, isGuest: isGuest, codeState: referralState,
                      message: referralMessage, isFocused: $isNameFocused,
                      onCodeComplete: { checkReferralCode() },
                      onBadCodeShown: { referralCode = "" })
            .onChange(of: referralCode) { _, value in
                referralMessage = nil
                if referralChecked != value { referralChecked = nil }
            }
            .onAppear { isNameFocused = true }
    }

    /// Finds out whether the code works, without using it or leaving the step.
    private func checkReferralCode() {
        let code = referralCode.trimmingCharacters(in: .whitespaces)
        guard code.count == 6, !isTestingCode else { return }
        isTestingCode = true
        referralMessage = nil
        Task {
            defer { isTestingCode = false }
            do {
                try await SupabaseSDK.checkReferralCode(code)
                referralChecked = code
            } catch {
                referralMessage = ReferralFailure.message(for: error)
            }
        }
    }

    /// Goes to step 2; a typed code is checked first and a wrong one keeps the user here with the reason.
    private func continueFromName() {
        guard !isCheckingCode else { return }
        let code = referralCode.trimmingCharacters(in: .whitespaces)
        guard onBack == nil, !code.isEmpty, !referralAccepted else { move(to: 2); return }
        isCheckingCode = true
        Task {
            defer { isCheckingCode = false }
            do {
                try await SupabaseSDK.redeemReferralCode(code)
                referralAccepted = true
                move(to: 2)
            } catch {
                referralMessage = ReferralFailure.message(for: error)
            }
        }
    }

    // MARK: - 2 · Wallets

    private var walletStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                heading(L("Dompet apa yang kamu pakai?"), nil, size: 30)
                    .padding(.top, 20)

                pocketPreview
                    .padding(.top, 22)

                Text(picked.isEmpty ? L("Belum ada dompet dipilih") : L("%lld dompet dipilih", picked.count))
                    .font(.app(14))
                    .foregroundStyle(Color.appTextSecondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: picked.count)
                    .padding(.top, 12)

                if let note = walletNote {
                    Text(note)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 6)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(GuestWallet.groups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L(group.name))
                                .font(.app(13))
                                .tracking(0.2)
                                .foregroundStyle(Color.appTextSecondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(group.items) { walletTile($0) }
                            }
                        }
                        .padding(.top, 22)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    /// One line under the count: the Free plan limit when it cuts picks off, else where to finish a card.
    private var walletNote: String? {
        if isOverFreeLimit {
            return L("Paket Gratis: maksimal %lld dompet uang dan %lld Dompet Investasi, sisanya tidak dibuat.",
                     FreeLimits.moneyWallets, FreeLimits.investmentWallets)
        }
        return picked.contains("credit") ? L("Lengkapi detailnya di Dompet") : nil
    }

    /// The three latest picks fan out of a green pocket; the rest fade away inside it.
    private var pocketPreview: some View {
        let top3 = Array(picked.suffix(3).reversed())
        let slots: [(width: CGFloat, top: CGFloat, angle: Double, x: CGFloat)] = [(209, 60, 0, 0), (189, 30, 4, 9), (168, 0, -7, -12)]
        return ZStack(alignment: .topLeading) {
            ForEach(GuestWallet.all) { w in
                let rank = top3.firstIndex(of: w.id)
                let slot = rank.map { slots[$0] } ?? (168, 110, 0, 0)
                RoundedRectangle(cornerRadius: 12)
                    .fill(w.color)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: "F3D48A"))
                            .frame(width: 18, height: 13)
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(w.short)
                            .font(.app(10, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                    .frame(width: slot.width, height: 115)
                    .shadow(color: .black.opacity(0.16), radius: 5, y: -3)
                    .opacity(rank == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: rank)
                    .rotationEffect(.degrees(slot.angle))
                    .offset(x: (230 - slot.width) / 2 + slot.x, y: slot.top)
                    .zIndex(Double(rank.map { 3 - $0 } ?? 0))
                    .animation(.settle(0.62), value: rank)
            }

            PocketShape(curve: 97 / 131)
                .fill(Color.appBrand)
                .overlay(alignment: .top) {
                    DashedLine()
                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        .frame(height: 2.5)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                }
                .frame(width: 230, height: 131)
                .offset(y: 99)
                .zIndex(5)
        }
        .frame(width: 230, height: 230, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func walletTile(_ w: GuestWallet) -> some View {
        let on = picked.contains(w.id)
        return Button { toggle(w.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(on ? Color.white.opacity(0.35) : w.color)
                    .frame(width: 22, height: 14)
                Spacer(minLength: 0)
                Text(w.type == .credit ? L(w.name) : w.name)
                    .font(.app(14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 78)
            .foregroundStyle(on ? Color.white : Color.appText)
            .background(on ? w.color : Color.appFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(w.color)
                    }
                    .padding(10)
                    .opacity(on ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: on)
                    .scaleEffect(on ? 1 : 0.3)
                    .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: on)
            }
            .shadow(color: on ? w.color.opacity(0.32) : .clear, radius: 9, y: 8)
            .animation(.easeInOut(duration: 0.26), value: on)
            .offset(y: on ? -2 : 0)
            .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.32), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ id: String) {
        if let i = picked.firstIndex(of: id) {
            picked.remove(at: i)
            if focusedCard == id { focusedCard = nil }
        } else {
            picked.append(id)
            focusedCard = id
        }
    }

    // MARK: - 3 · Balances

    private var balanceStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading(L("Berapa saldonya sekarang?"), L("Kira-kira saja, nanti bisa disesuaikan."), size: 30)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Total saldo · \(balanceWallets.count) akun")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    HStack(alignment: .top, spacing: 4) {
                        Text("Rp")
                            .font(.app(22))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.top, 8)
                        CountingText(value: total) { $0.formattedAsDigits() }
                            .font(.app(52, weight: .light))
                            .tracking(-2)
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.6), value: total)
                    }
                    .monospacedDigit()
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

                VStack(spacing: 0) {
                    ForEach(Array(balanceWallets.enumerated()), id: \.element.id) { i, w in
                        balanceCard(w)
                            .padding(.top, i == 0 ? 0 : -10)
                            .zIndex(Double(i))
                    }
                    Text("Ketuk kartu untuk mengubah saldo")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private static let chips: [(label: String, value: Double)] = [("+50 rb", 50_000), ("+100 rb", 100_000), ("+1 jt", 1_000_000), ("Reset", 0)]

    private func balanceCard(_ w: GuestWallet) -> some View {
        let isOpen = focusedCard == w.id
        let amount = amounts[w.id] ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(w.name).font(.app(15, weight: .bold))
                    Text(w.type == .cash ? "Cash" : w.type.rawValue).font(.app(12)).opacity(0.78)
                }
                Spacer()
                Text("Rp" + amount.formattedAsDigits())
                    .font(.app(17, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .opacity(isOpen ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isOpen)
            }
            .frame(height: 64)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 3) {
                    Text("Rp").font(.app(17)).opacity(0.8).padding(.top, 5)
                    Text(amount.formattedAsDigits())
                        .font(.app(36, weight: .light))
                        .tracking(-1.2)
                        .contentTransition(.numericText())
                }
                .monospacedDigit()

                HStack(spacing: 6) {
                    ForEach(Self.chips, id: \.label) { chip in
                        Button {
                            withAnimation(.snappy) {
                                focusedCard = w.id
                                amounts[w.id] = chip.value == 0 ? 0 : amount + chip.value
                            }
                        } label: {
                            Text(L(chip.label))
                                .font(.app(13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .opacity(isOpen ? 1 : 0)
            .animation(.easeInOut(duration: 0.28).delay(0.14), value: isOpen)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isOpen ? 172 : 64, alignment: .top)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(w.color)
                .overlay(alignment: .topTrailing) {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 220, height: 220)
                        .offset(x: 50, y: -70)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.14), radius: 6, y: -3)
        .animation(.settle(0.48), value: isOpen)
        .contentShape(Rectangle())
        .onTapGesture { focusedCard = isOpen ? nil : w.id }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(w.name), Rp\(amount.formattedAsDigits())")
    }
}

// MARK: - 4 · Categories, 5 · Payday

extension SetupOnboardingView {
    /// Same idea as picking wallets: a pocket the first picks fan out of, then tiles to toggle.
    /// Everything starts selected; unselect what you won't use.
    fileprivate var categoryStep: some View {
        ScrollView {
            VStack(spacing: 0) {
                heading(L("Kategori apa yang kamu pakai?"), nil, size: 30)
                    .padding(.top, 20)

                categoryPocket
                    .padding(.top, 22)

                Text("\(selectedCategories.count) kategori dipilih")
                    .font(.app(14))
                    .foregroundStyle(Color.appTextSecondary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: selectedCategories.count)
                    .padding(.top, 12)
                Text("Lepas yang tidak perlu. Bisa diubah lagi di Profil › Kategori.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 0) {
                    categoryGroup(L("Pengeluaran"), OnboardingCategory.expense, count: selectedExpenseCount, offset: 0)
                    categoryGroup(L("Pemasukan"), OnboardingCategory.income, count: selectedIncomeCount,
                                  offset: OnboardingCategory.expense.count)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .onAppear { categoriesEntered = true }
        .onDisappear { categoriesEntered = false }
    }

    /// The first three selected categories rise out of the pocket; unselecting one drops it in
    /// and the next takes its place.
    private var categoryPocket: some View {
        let top3 = OnboardingCategory.all.filter { selectedCategories.contains($0.key) }.prefix(3).map(\.key)
        let slots: [(width: CGFloat, top: CGFloat, angle: Double, x: CGFloat)] = [(209, 60, 0, 0), (189, 30, 4, 9), (168, 0, -7, -12)]
        return ZStack(alignment: .topLeading) {
            ForEach(OnboardingCategory.all) { c in
                let rank = top3.firstIndex(of: c.key)
                let slot = rank.map { slots[$0] } ?? (168, 110, 0, 0)
                RoundedRectangle(cornerRadius: 12)
                    .fill(c.color)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: c.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(c.name.uppercased())
                            .font(.app(10, weight: .heavy))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(10)
                            .padding(.leading, 30)
                    }
                    .frame(width: slot.width, height: 115)
                    .shadow(color: .black.opacity(0.16), radius: 5, y: -3)
                    .opacity(rank == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.3), value: rank)
                    .rotationEffect(.degrees(slot.angle))
                    .offset(x: (230 - slot.width) / 2 + slot.x, y: slot.top)
                    .zIndex(Double(rank.map { 3 - $0 } ?? 0))
                    .animation(.settle(0.62), value: rank)
            }

            PocketShape(curve: 97 / 131)
                .fill(Color.appBrand)
                .overlay(alignment: .top) {
                    DashedLine()
                        .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        .frame(height: 2.5)
                        .padding(.horizontal, 26)
                        .padding(.top, 18)
                }
                .frame(width: 230, height: 131)
                .offset(y: 99)
                .zIndex(5)
        }
        .frame(width: 230, height: 230, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func categoryGroup(_ title: String, _ items: [OnboardingCategory], count: Int, offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.app(13))
                    .tracking(0.2)
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
                Text("\(count) dari \(items.count)")
                    .font(.app(13))
                    .foregroundStyle(count == 0 ? Color.appError : Color.appTextSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: count)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    categoryTile(item)
                        .opacity(categoriesEntered ? 1 : 0)
                        .offset(y: categoriesEntered ? 0 : 16)
                        .animation(.settle(0.5).delay(Double(offset + index) * 0.03), value: categoriesEntered)
                }
            }
        }
        .padding(.top, 22)
    }

    /// Wallet-tile style: lifts and fills with its colour when on, with a check that springs in.
    private func categoryTile(_ c: OnboardingCategory) -> some View {
        let on = selectedCategories.contains(c.key)
        return Button {
            if on { selectedCategories.remove(c.key) } else { selectedCategories.insert(c.key) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: c.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(on ? Color.white.opacity(0.9) : c.color)
                    .frame(height: 20)
                Spacer(minLength: 0)
                Text(c.name)
                    .font(.app(13, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 86)
            .foregroundStyle(on ? Color.white : Color.appText)
            .background(on ? c.color : Color.appFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(c.color)
                    }
                    .padding(10)
                    .opacity(on ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: on)
                    .scaleEffect(on ? 1 : 0.3)
                    .animation(.timingCurve(0.3, 1.5, 0.5, 1, duration: 0.32), value: on)
            }
            .shadow(color: on ? c.color.opacity(0.32) : .clear, radius: 9, y: 8)
            .animation(.easeInOut(duration: 0.26), value: on)
            .offset(y: on ? -2 : 0)
            .animation(.timingCurve(0.3, 1.3, 0.5, 1, duration: 0.32), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Wallet offered in guest setup; `iconId` maps onto `WalletIcon` so the saved
/// account shows the same logo elsewhere in the app.
private struct GuestWallet: Identifiable {
    let id: String
    let name: String
    let hex: String
    let type: Account.AccountType

    var color: Color { Color(hex: hex) }
    var short: String { type == .cash ? "CASH" : type == .credit ? "KARTU" : name.uppercased() }
    /// Empty for a card: it has no brand until its details are filled in under Dompet.
    var iconId: String { id == "credit" ? "" : id == "shopeepay" ? WalletIcon.customIconId(text: "ShopeePay", colorName: "jingga") : id }

    static let groups: [(name: String, items: [GuestWallet])] = [
        ("Bank", [
            GuestWallet(id: "bca", name: "BCA", hex: "0066AE", type: .bank),
            GuestWallet(id: "mandiri", name: "Mandiri", hex: "003D79", type: .bank),
            GuestWallet(id: "bri", name: "BRI", hex: "00529C", type: .bank),
            GuestWallet(id: "bni", name: "BNI", hex: "F15A23", type: .bank),
            GuestWallet(id: "jago", name: "Jago", hex: "00A86B", type: .bank),
        ]),
        ("E-Wallet", [
            GuestWallet(id: "gopay", name: "GoPay", hex: "00AA44", type: .ewallet),
            GuestWallet(id: "ovo", name: "OVO", hex: "472B91", type: .ewallet),
            GuestWallet(id: "dana", name: "DANA", hex: "118EEA", type: .ewallet),
            GuestWallet(id: "shopeepay", name: "ShopeePay", hex: "EE4D2D", type: .ewallet),
        ]),
        ("Cash", [
            GuestWallet(id: "cash", name: "Dompet tunai", hex: "616161", type: .cash),
        ]),
        ("Kartu kredit", [
            GuestWallet(id: "credit", name: "Kartu kredit", hex: "1A1F71", type: .credit),
        ]),
        ("Investasi", [
            GuestWallet(id: "bibit", name: "Bibit", hex: "00875A", type: .investment),
            GuestWallet(id: "stockbit", name: "Stockbit", hex: "2E3A46", type: .investment),
            GuestWallet(id: "emas", name: "Emas", hex: "946200", type: .investment),
        ]),
    ]

    static let all = groups.flatMap(\.items)
}

/// One of the four bars on the saving screen, fading in and out.
private struct PulsingSegment: View {
    let delay: Double
    @State private var lit = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.appPrimary)
            .frame(height: 4)
            .opacity(lit ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay), value: lit)
            .onAppear { lit = true }
    }
}

/// The red cross on the failure screen, shaking once.
private struct ShakingBadge: View {
    @State private var shakes = 0

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Color.appError)
            .frame(width: 72, height: 72)
            .background(Color.appError.opacity(0.12), in: Circle())
            .modifier(ShakeEffect(shakes: CGFloat(shakes)))
            .onAppear { withAnimation(.settle(0.5).delay(0.15)) { shakes = 1 } }
    }
}
