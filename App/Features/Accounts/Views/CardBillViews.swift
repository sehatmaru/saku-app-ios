import SwiftUI

// MARK: - Card bill

extension CreditStatement {
    var statusText: String {
        switch status {
        case .none: "Tidak ada tagihan"
        case .unpaid: "Belum dibayar"
        case .partial: "Dibayar sebagian"
        case .paid: "Lunas"
        case .overdue: "Terlambat"
        }
    }

    var statusColor: Color {
        switch status {
        case .overdue: .appError
        case .paid: .appPrimary
        default: .appTextSecondary
        }
    }

    /// "Jatuh tempo 20 Okt · 3 hari lagi"; the countdown only while something is owed.
    var dueText: String {
        let due = "Jatuh tempo " + TransactionDates.dayMonth.string(from: dueDate)
        guard status == .unpaid || status == .partial || status == .overdue else { return due }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: dueDate).day ?? 0
        let left = switch days {
        case ..<0: "lewat \(-days) hari"
        case 0: "hari ini"
        case 1: "besok"
        default: "\(days) hari lagi"
        }
        return due + " · " + left
    }
}

/// What's still owed on a card's last statement, its status and due date.
struct CardBillSummary: View {
    let statement: CreditStatement
    var isVisible = true
    /// One line for the Dompet card overlay.
    var compact = false

    private var title: String { "Tagihan " + TransactionDates.dayMonth.string(from: statement.statementDate) }

    var body: some View {
        if compact {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(isVisible ? statement.remaining.formattedAsCurrency() : "Rp" + hiddenAmount)
                        .font(.app(20, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.appText)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statement.statusText)
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(statement.statusColor)
                    Text(statement.dueText)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                HeroAmount(value: statement.remaining, size: .medium, isVisible: isVisible)
                Text(statement.statusText)
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(statement.statusColor)
                Text(statement.dueText)
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .monospacedDigit()
                if statement.status == .partial {
                    Text("Sudah dibayar " + (isVisible ? statement.paid.formattedAsCurrency() : "Rp" + hiddenAmount))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Pays a card bill (design 1d): a transfer from a cash wallet into the card, which lowers its debt.
struct PayCardBillSheet: View {
    let card: Account
    let statement: CreditStatement
    let wallets: [Account]
    /// Called after a successful payment with the amount and the wallet it came from.
    var onPaid: ((Double, Account) -> Void)? = nil

    private enum Choice { case full, minimum, custom }

    @State private var choice = Choice.full
    @State private var customAmount = 0
    /// The first key press after choosing "Nominal lain" starts a new number.
    @State private var isFresh = true
    @State private var isPadOpen = false
    @State private var bump = false
    @State private var sourceId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @Environment(\.dismiss) private var dismiss

    private var sources: [Account] { wallets.filter { $0.isActive && !$0.isCreditCard } }
    private var source: Account? { sources.first { $0.id == sourceId } }
    /// Nothing billed yet but the card has debt: offer paying all of it.
    private var fullAmount: Double { statement.remaining > 0 ? statement.remaining : card.balance }
    private var showsMinimum: Bool { statement.minimumDue > 0 && statement.minimumDue < statement.remaining }

    private var amount: Double {
        switch choice {
        case .full: fullAmount
        case .minimum: statement.minimumDue
        case .custom: Double(customAmount)
        }
    }

    private var shortfall: Double { max(amount - (source?.balance ?? 0), 0) }
    private var canPay: Bool { amount > 0 && source != nil && shortfall == 0 && !isSaving }

    private var buttonTitle: String {
        if source == nil { return "Pilih dompet" }
        if amount <= 0 { return "Masukkan nominal" }
        if shortfall > 0 { return "Saldo tidak cukup" }
        return "Bayar " + amount.formattedAsCurrency()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
                Spacer()
            }
            .overlay {
                Text("Bayar tagihan")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 13)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    amountHeader
                    modeRows
                    if statement.remaining > 0, amount > 0, amount < statement.remaining {
                        let left = statement.remaining - amount
                        Text("Sisa \(left.formattedAsCurrency()) kena bunga sekitar \((left * CreditStatement.monthlyInterest).formattedAsCurrency())/bulan")
                            .font(.app(13))
                            .foregroundStyle(Color.appWarning)
                            .monospacedDigit()
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                    if !isPadOpen {
                        sourceSection
                            .transition(.opacity)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.app(13))
                            .foregroundStyle(Color.appError)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

            if isPadOpen {
                PayPad(onPress: press) {
                    withAnimation(.settle(0.4)) { isPadOpen = false }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                payButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
        .onAppear {
            if sourceId == nil { sourceId = (sources.first(where: \.isDefault) ?? sources.first)?.id }
        }
    }

    // MARK: Amount

    private var amountHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text("Rp")
                    .font(.app(20))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 7)
                Text(amount.formattedAsDigits())
                    .font(.app(48, weight: .light))
                    .tracking(-1.8)
                    .foregroundStyle(amount > 0 ? Color.appText : Color.appTextTertiary)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .scaleEffect(bump ? 1.04 : 1, anchor: .leading)
            .animation(.easeOut(duration: 0.14), value: bump)
            Text("ke \(card.name)")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
    }

    // MARK: Modes

    private var modeRows: some View {
        VStack(spacing: 0) {
            modeRow(.full, title: "Bayar penuh",
                    caption: statement.remaining > 0 ? "Sisa tagihan" : "Seluruh utang kartu",
                    value: fullAmount.formattedAsCurrency())
            if showsMinimum {
                modeRow(.minimum, title: "Bayar minimum", caption: "Pembayaran minimum",
                        value: statement.minimumDue.formattedAsCurrency())
            }
            modeRow(.custom, title: "Nominal lain", caption: "Ketik sendiri",
                    value: choice == .custom && customAmount > 0 ? Double(customAmount).formattedAsCurrency() : "")
        }
        .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }
    }

    private func modeRow(_ value: Choice, title: String, caption: String, value text: String) -> some View {
        let isOn = choice == value
        return Button {
            withAnimation(.settle(0.4)) {
                choice = value
                isPadOpen = value == .custom
                if value == .custom { isFresh = true }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(16, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(Color.appText)
                    Text(caption)
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                Text(text)
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.appPrimary)
                    .opacity(isOn ? 1 : 0)
                    .scaleEffect(isOn ? 1 : 0.4)
                    .animation(.spring(duration: 0.38, bounce: 0.5), value: isOn)
            }
            .frame(height: 64)
            .padding(.horizontal, 24)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bayar dari")
                .font(.app(20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Color.appText)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 10)
            if sources.isEmpty {
                Text("Belum ada dompet untuk membayar")
                    .font(.app(15))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.horizontal, 24)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sources) { wallet in
                            SourceCard(account: wallet, isSelected: wallet.id == sourceId, isBalanceVisible: isBalanceVisible) {
                                sourceId = wallet.id
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                }
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14))
                    Text("Saldo \(source?.name ?? "") kurang \(shortfall.formattedAsCurrency())")
                        .monospacedDigit()
                }
                .font(.app(13))
                .foregroundStyle(Color.appError)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .opacity(shortfall > 0 && source != nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: shortfall > 0)
            }
        }
    }

    private var payButton: some View {
        Button(action: pay) {
            Group {
                if isSaving { ProgressView().tint(.white) } else { Text(buttonTitle) }
            }
            .font(.app(17, weight: .semibold))
            .foregroundStyle(canPay || isSaving ? Color.white : Color.appTextSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canPay || isSaving ? Color.appPrimary : Color(light: 0xE5E5EA, dark: 0x3A3A3C), in: Capsule())
            .animation(.easeInOut(duration: 0.22), value: canPay)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!canPay)
    }

    // MARK: Logic

    private func press(_ key: String) {
        let base = isFresh ? 0 : customAmount
        guard let next = NumberPad.apply(key, to: base) else { return }
        isFresh = false
        withAnimation(.easeOut(duration: 0.14)) { customAmount = next }
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            bump = false
        }
    }

    private func pay() {
        guard canPay, let source else { return }
        let paid = amount
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await SupabaseRepository.shared.createTransfer(
                    primaryAccountId: source.id, counterpartyAccountId: card.id, amount: paid,
                    description: "Bayar tagihan \(card.name)", note: nil, date: Date()
                )
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onPaid?(paid, source)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = "Gagal membayar tagihan. Coba lagi."
            }
        }
    }
}

/// 156×96 wallet card to pay from: ringed and full size when chosen, a touch smaller otherwise.
private struct SourceCard: View {
    let account: Account
    let isSelected: Bool
    let isBalanceVisible: Bool
    let action: () -> Void

    var body: some View {
        let color = account.walletColor
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 34, height: 22)
                        .overlay {
                            if let logo = account.brandLogo {
                                Image(logo).resizable().scaledToFit().frame(width: 26, height: 14)
                            } else {
                                Image(systemName: account.typeSymbol)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(color)
                            }
                        }
                    Spacer()
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(color)
                        }
                        .scaleEffect(isSelected ? 1 : 0.001)
                        .animation(.spring(duration: 0.42, bounce: 0.5), value: isSelected)
                }
                Spacer(minLength: 0)
                Text(account.name)
                    .font(.app(15, weight: .semibold))
                    .lineLimit(1)
                Text(isBalanceVisible ? account.balance.formattedAsCurrency() : "Rp" + hiddenAmount)
                    .font(.app(13))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 156, height: 96, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color)
                    .overlay(
                        LinearGradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: account.typeSymbol)
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(.white.opacity(0.08))
                            .offset(x: 10, y: 14)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            // 2pt gap in the sheet colour, then a 2pt ring in the wallet colour.
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(color).padding(-4)
                    RoundedRectangle(cornerRadius: 18).fill(Color.appBackground).padding(-2)
                }
                .opacity(isSelected ? 1 : 0)
                .animation(.easeInOut(duration: 0.22), value: isSelected)
            }
            .scaleEffect(isSelected ? 1 : 0.96)
            .animation(.spring(duration: 0.38, bounce: 0.45), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), saldo \(account.balance.formattedAsCurrency())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Number keys with a green Selesai key, for "Nominal lain".
private struct PayPad: View {
    let onPress: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        GeometryReader { geo in
            let doneWidth = (geo.size.width - 6) / 4
            HStack(spacing: 6) {
                NumberPadKeys(onPress: onPress)
                    .frame(width: geo.size.width - doneWidth - 6)
                Button(action: onDone) {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                        Text("Selesai").font(.app(14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appPrimary, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(PressScaleStyle())
                .frame(width: doneWidth)
            }
        }
        .frame(height: 52 * 4 + 6 * 3)
    }
}
