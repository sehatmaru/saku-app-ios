import SwiftUI

// MARK: - Card bill

extension CreditStatement {
    var statusText: String {
        switch status {
        case .none: L("Tidak ada tagihan")
        case .unpaid: L("Belum dibayar")
        case .partial: L("Dibayar sebagian")
        case .paid: L("Lunas")
        case .overdue: L("Terlambat")
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
        let due = L("Jatuh tempo %@", TransactionDates.dayMonth.string(from: dueDate))
        guard status == .unpaid || status == .partial || status == .overdue else { return due }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: dueDate).day ?? 0
        let left = switch days {
        case ..<0: L("lewat %lld hari", -days)
        case 0: L("hari ini")
        case 1: L("besok")
        default: L("%lld hari lagi", days)
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

    private var title: String { L("Tagihan %@", TransactionDates.dayMonth.string(from: statement.statementDate)) }

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
                    Text(L("Sudah dibayar %@", isVisible ? statement.paid.formattedAsCurrency() : "Rp" + hiddenAmount))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Pays a card bill full-screen (design 1e): a transfer from a cash wallet into the card, which lowers its debt.
/// In `.record` mode (Pengingat Tagihan 2c) it instead notes a bill that was already paid: on a past
/// date, and possibly from outside Saku, which moves no wallet.
struct PayCardBillSheet: View {
    enum Mode { case pay, record }

    let card: Account
    let statement: CreditStatement
    let wallets: [Account]
    var mode: Mode = .pay
    /// Called after a successful payment, just before the screen closes, with the amount, the wallet it
    /// came from (nil for "Sumber lain"), and whether the statement is now fully paid.
    var onPaid: ((Double, Account?, Bool) -> Void)? = nil

    private enum Choice { case full, minimum, custom }

    @State private var choice = Choice.full
    @State private var customAmount = 0
    /// The first key press after switching to "Nominal lain" starts a new number.
    @State private var isFresh = true
    @State private var bump = false
    @State private var shake: CGFloat = 0
    @State private var sourceId: String?
    @State private var noteText = ""
    @State private var showSourceSheet = false
    @State private var isOtherSource = false
    @State private var paidOn: Date?
    @State private var showDateSheet = false
    @State private var isSourceFlashing = false
    @State private var hasEntered = false
    @State private var isSaving = false
    @State private var isDone = false
    @State private var swipeReset = 0
    /// Done-state lines, fixed at success so the reload after paying doesn't change them.
    @State private var doneLines = ("", "")
    @State private var errorMessage: String?
    @FocusState private var isNoteFocused: Bool
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true
    @Environment(\.dismiss) private var dismiss

    private var isRecord: Bool { mode == .record }
    private var sources: [Account] { wallets.filter { $0.isActive && !$0.isCreditCard } }
    private var source: Account? { isOtherSource ? nil : sources.first { $0.id == sourceId } }
    private var color: Color { isOtherSource ? Color(hex: "48484A") : source?.walletColor ?? .appPrimary }
    /// Nothing billed yet but the card has debt: offer paying all of it.
    private var fullAmount: Double { statement.remaining > 0 || isRecord ? statement.remaining : card.balance }
    private var showsMinimum: Bool { !isRecord && statement.minimumDue > 0 && statement.minimumDue < statement.remaining }
    /// Paying unbilled charges early is fine; more than the whole debt isn't. A recorded payment answers
    /// one statement, so it can't exceed what that statement still owes.
    private var maxPayable: Double { isRecord ? statement.remaining : max(card.balance, statement.remaining) }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    /// The day the bill was paid; the due date until the user picks another, but never in the future.
    private var payDate: Date { paidOn ?? min(statement.dueDate, today) }
    /// The first day a payment can count for this statement, and the last.
    private var payRange: ClosedRange<Date> {
        let first = Calendar.current.date(byAdding: .day, value: 1, to: statement.statementDate) ?? statement.statementDate
        return min(first, today)...today
    }

    private var amount: Double {
        switch choice {
        case .full: fullAmount
        case .minimum: statement.minimumDue
        case .custom: Double(customAmount)
        }
    }

    private var sourceBalance: Double { source?.balance ?? 0 }
    private var shortfall: Double { source == nil ? 0 : max(amount - sourceBalance, 0) }
    private var isOverDebt: Bool { amount > maxPayable + 0.5 }
    private var isBlocked: Bool { shortfall > 0 || isOverDebt }
    private var canPay: Bool { amount > 0 && (source != nil || isOtherSource) && !isBlocked }
    private var remainingAfter: Double { max(statement.remaining - amount, 0) }

    private var sliderLabel: String {
        if source == nil, !isOtherSource { return L("Pilih dompet") }
        if amount <= 0 { return L("Masukkan nominal") }
        if shortfall > 0 { return L("Saldo tidak cukup") }
        if isOverDebt { return isRecord ? L("Melebihi tagihan") : L("Melebihi utang") }
        return isRecord ? L("Geser untuk catat") : L("Geser untuk bayar")
    }

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            panel
            rows
                .padding(.top, 10)
                .opacity(isDone ? 0 : 1)
                .animation(.easeOut(duration: 0.3), value: isDone)
            Group {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.appError)
                } else if statement.remaining > 0, amount > 0, amount < statement.remaining, !isDone {
                    Text("Sisa \(remainingAfter.formattedAsCurrency()) kena bunga sekitar \((remainingAfter * CreditStatement.monthlyInterest).formattedAsCurrency())/bulan")
                        .foregroundStyle(Color.appWarning)
                }
            }
            .font(.app(13))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.2), value: amount)
            Spacer(minLength: 8)
            VStack(spacing: 10) {
                NumberPadKeys(onPress: press)
                SwipeToConfirm(label: sliderLabel, color: color, isEnabled: canPay && !isSaving,
                               resetToken: swipeReset, onBlocked: blocked, onConfirm: pay)
                    .offset(x: shake)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            if sourceId == nil { sourceId = (sources.first(where: \.isDefault) ?? sources.first)?.id }
            hasEntered = true
        }
        .sheet(isPresented: $showSourceSheet) { sourceSheet }
        .sheet(isPresented: $showDateSheet) {
            BillDateSheet(range: payRange, dueDate: statement.dueDate, color: card.walletColor, selected: payDate) { day in
                paidOn = day
                showDateSheet = false
            }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(.white)
                    .disabled(isSaving)
                Spacer()
            }
            .overlay {
                HStack(spacing: 8) {
                    Image(systemName: isRecord ? "receipt" : "creditcard").font(.system(size: 15, weight: .bold))
                    Text(isRecord ? "Catat tagihan" : "Bayar tagihan").font(.app(17, weight: .semibold))
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 20)

            ZStack(alignment: .top) {
                panelContent
                    .opacity(isDone ? 0 : 1)
                    .offset(y: isDone ? -14 : 0)
                    .scaleEffect(isDone ? 0.97 : 1)
                    .animation(.settle(0.42), value: isDone)
                doneContent
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(height: isRecord ? 312 : 266)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32)
                .fill(color)
                .overlay {
                    LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isRecord ? "receipt" : "creditcard")
                        .font(.system(size: 170, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.06))
                        .offset(x: 40, y: 90)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32))
                .animation(.easeInOut(duration: 0.45), value: sourceId)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func swatch(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: 16, height: 11)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.6), lineWidth: 1))
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                swatch(color)
                Text(isOtherSource ? L("Sumber lain") : source?.name ?? L("Pilih dompet")).lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.7)
                swatch(card.walletColor)
                Text(card.name).lineLimit(1)
            }
            .font(.app(13, weight: .medium))
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 28)
            .background(.white.opacity(0.14), in: Capsule())
            .padding(.horizontal, 24)
            .padding(.top, 6)

            if isRecord {
                Text("Tagihan cut-off \(TransactionDates.dayMonth.string(from: statement.statementDate)), jatuh tempo \(TransactionDates.dayMonth.string(from: statement.dueDate))")
                    .font(.app(13))
                    .opacity(0.82)
                    .padding(.top, 8)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("Rp")
                    .font(.app(22))
                    .opacity(0.75)
                    .padding(.top, 8)
                Text(amount.formattedAsDigits())
                    .font(.app(56, weight: .light))
                    .tracking(-2)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(amount > 0 ? 1 : 0.55)
            .scaleEffect(bump ? 1.04 : 1)
            .offset(x: shake)
            .animation(.easeOut(duration: 0.12), value: bump)
            .animation(.easeOut(duration: 0.2), value: amount > 0)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ViewThatFits(in: .horizontal) {
                modeChips.padding(.horizontal, 24)
                ScrollView(.horizontal, showsIndicators: false) {
                    modeChips.padding(.horizontal, 24)
                }
            }
            .padding(.top, 14)

            ZStack(alignment: .top) {
                VStack(spacing: 6) {
                    if isRecord {
                        infoRow(isOtherSource ? L("Sumber lain") : L("Saldo %@", source?.name ?? ""),
                                isOtherSource ? L("Tidak mengurangi saldo") : "\(money(sourceBalance)) → \(money(max(sourceBalance - amount, 0)))")
                        infoRow(L("Terpakai %@", card.name),
                                "\(money(card.balance)) → \(money(max(card.balance - amount, 0)))")
                        infoRow(L("Status"), recordStatusText)
                    } else {
                        infoRow(L("Saldo %@", source?.name ?? ""),
                                "\(money(sourceBalance)) → \(money(max(sourceBalance - amount, 0)))")
                        infoRow(L("Sisa tagihan"),
                                "\(money(statement.remaining)) → \(money(remainingAfter))")
                    }
                }
                .opacity(isBlocked ? 0 : 1)
                warningPill
                    .padding(.top, 6)
            }
            .frame(height: isRecord ? 66 : 44, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .animation(.easeInOut(duration: 0.22), value: isBlocked)
        }
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            modeChip(.full, isRecord ? L("Lunas penuh %@", fullAmount.formattedAsCurrency()) : L("Bayar penuh %@", fullAmount.formattedAsCurrency()))
            if showsMinimum { modeChip(.minimum, L("Minimum %@", statement.minimumDue.formattedAsCurrency())) }
            modeChip(.custom, isRecord && choice == .custom && amount > 0 && amount < statement.remaining ? L("Sebagian") : L("Nominal lain"))
        }
    }

    private var recordStatusText: String {
        if amount >= statement.remaining, amount > 0 { return L("Lewat jatuh tempo → Lunas") }
        if amount > 0 { return L("→ Sebagian · sisa %@", money(remainingAfter)) }
        return L("Lewat jatuh tempo")
    }

    private func modeChip(_ value: Choice, _ title: String) -> some View {
        let isOn = choice == value
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                choice = value
                if value == .custom { customAmount = 0; isFresh = true }
            }
        } label: {
            Text(title)
                .font(.app(14, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(isOn ? color : .white)
                .padding(.horizontal, showsMinimum ? 12 : 14)
                .frame(height: 32)
                .background(isOn ? Color.white : Color.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(isDone || isSaving)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).opacity(0.85).lineLimit(1)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).lineLimit(1)
        }
        .font(.app(13))
        .monospacedDigit()
    }

    private var warningPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 15))
            Text(shortfall > 0 ? L("Saldo %@ kurang %@", source?.name ?? "", shortfall.formattedAsCurrency()) + (isRecord ? L(" · pilih dompet lain") : "")
                               : (isRecord ? L("Melebihi sisa tagihan %@", maxPayable.formattedAsCurrency()) : L("Melebihi utang kartu %@", maxPayable.formattedAsCurrency())))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.app(13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color(hex: "D93025"))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .opacity(isBlocked ? 1 : 0)
        .scaleEffect(isBlocked ? 1 : 0.96)
        .offset(y: isBlocked ? 0 : 6)
        .animation(.spring(duration: 0.38, bounce: 0.45), value: isBlocked)
    }

    private var doneContent: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.white)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(color)
                }
                .scaleEffect(isDone ? 1 : 0.4)
                .animation(.spring(duration: 0.56, bounce: 0.5), value: isDone)
            Text(isRecord ? L("Pembayaran tercatat") : L("Pembayaran berhasil"))
                .font(.app(20, weight: .semibold))
                .padding(.top, 6)
            Text(doneLines.0)
                .font(.app(14))
                .opacity(0.85)
            Text(doneLines.1)
                .font(.app(13))
                .opacity(0.75)
        }
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .opacity(isDone ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isDone)
        .allowsHitTesting(false)
    }

    // MARK: Rows

    private func entering<V: View>(_ view: V, index: Int) -> some View {
        view
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered ? 0 : 14)
            .animation(.settle(0.5).delay(Double(index) * 0.06 + 0.2), value: hasEntered)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .frame(width: isRecord ? 96 : 76, alignment: .leading)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            entering(sourceRow, index: 0)
            if isRecord { entering(dateRow, index: 1) }
            entering(noteRow, index: isRecord ? 2 : 1)
        }
        .disabled(isDone || isSaving)
    }

    private var sourceRow: some View {
        Button {
            isNoteFocused = false
            showSourceSheet = true
        } label: {
            HStack(spacing: 12) {
                label(isRecord ? L("Dibayar dari") : L("Dari"))
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: 20, height: 14)
                    Text(isOtherSource ? L("Sumber lain") : source?.name ?? L("Pilih"))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(source == nil && !isOtherSource ? Color.appTextSecondary : Color.appText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if source != nil {
                    Text(money(sourceBalance))
                        .font(.app(14))
                        .monospacedDigit()
                        .foregroundStyle(Color.appTextSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .background(isSourceFlashing ? Color.appText.opacity(0.05) : .clear)
            .animation(.easeOut(duration: 0.45), value: isSourceFlashing)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(isOtherSource ? L("Sumber lain") : source?.name ?? L("Belum dipilih"))
    }

    /// Record mode: the day the bill was paid, defaulting to its due date.
    private var dateRow: some View {
        Button {
            isNoteFocused = false
            showDateSheet = true
        } label: {
            HStack(spacing: 12) {
                label(L("Tanggal bayar"))
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(Self.payDateFormatter.string(from: payDate))
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 8)
                Text(payDateHint)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(Self.payDateFormatter.string(from: payDate))
    }

    private var payDateHint: String {
        let calendar = Calendar.current
        if calendar.isDate(payDate, inSameDayAs: statement.dueDate) { return L("Jatuh tempo") }
        if calendar.isDate(payDate, inSameDayAs: today) { return L("Hari ini") }
        return ""
    }

    private static var payDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.dateFormat = "EEE, d MMM"
        return formatter
    }

    private var noteRow: some View {
        HStack(spacing: 12) {
            label(L("Catatan"))
            TextField("Opsional", text: $noteText)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .focused($isNoteFocused)
                .submitLabel(.done)
                .onChange(of: noteText) { _, new in
                    if new.count > 40 { noteText = String(new.prefix(40)) }
                }
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .contentShape(Rectangle())
        .onTapGesture { isNoteFocused = true }
    }

    // MARK: Source sheet

    private var sourceSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { showSourceSheet = false }
                    .font(.app(17))
                    .foregroundStyle(Color.appPrimary)
                Spacer()
            }
            .overlay {
                Text(isRecord ? L("Dibayar dari") : L("Bayar dari"))
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 13)

            ScrollView {
                if sources.isEmpty {
                    Text("Belum ada dompet untuk membayar")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 24)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(sources) { wallet in
                        SourceCard(account: wallet, isSelected: !isOtherSource && wallet.id == sourceId, isBalanceVisible: isBalanceVisible) {
                            sourceId = wallet.id
                            isOtherSource = false
                            Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                showSourceSheet = false
                                try? await Task.sleep(for: .milliseconds(250))
                                isSourceFlashing = true
                                try? await Task.sleep(for: .milliseconds(650))
                                isSourceFlashing = false
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, isRecord ? 4 : 16)
                if isRecord { otherSourceRow }
            }
        }
        .background(Color.appBackground)
        .presentationDetents([.height(min(CGFloat((sources.count + 1) / 2) * 108 + 110 + (isRecord ? 120 : 0), 700)), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appBackground)
    }

    /// Paid from an account outside Saku, or before the user started using it: no wallet moves.
    private var otherSourceRow: some View {
        Button {
            isOtherSource = true
            Task {
                try? await Task.sleep(for: .milliseconds(200))
                showSourceSheet = false
                try? await Task.sleep(for: .milliseconds(250))
                isSourceFlashing = true
                try? await Task.sleep(for: .milliseconds(650))
                isSourceFlashing = false
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.appBody)
                    .frame(width: 36, height: 36)
                    .background(Color.appBackground, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sumber lain")
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Text("Tidak mengurangi saldo. Pilih ini kalau tagihan dibayar dari rekening di luar Saku atau sebelum mulai pakai Saku.")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.appBackground)
                    .frame(width: 22, height: 22)
                    .background(Color.appText, in: Circle())
                    .scaleEffect(isOtherSource ? 1 : 0.001)
                    .animation(.spring(duration: 0.42, bounce: 0.5), value: isOtherSource)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appText, lineWidth: 2)
                    .opacity(isOtherSource ? 1 : 0)
                    .animation(.easeInOut(duration: 0.22), value: isOtherSource)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .accessibilityAddTraits(isOtherSource ? .isSelected : [])
    }

    // MARK: Logic

    private func press(_ key: String) {
        guard !isDone, !isSaving else { return }
        isNoteFocused = false
        var base = isFresh || choice != .custom ? 0 : customAmount
        if choice != .custom { withAnimation(.easeInOut(duration: 0.22)) { choice = .custom } }
        if key == "del", isFresh { base = 0 }
        guard let next = NumberPad.apply(key, to: base) else { return }
        isFresh = false
        withAnimation(.easeOut(duration: 0.14)) { customAmount = next }
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            bump = false
        }
    }

    private func blocked() {
        guard !isDone, !isSaving else { return }
        Task {
            for value: CGFloat in [-10, 9, -6, 4, 0] {
                withAnimation(.easeInOut(duration: 0.06)) { shake = value }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        if isBlocked { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        if source == nil, !isOtherSource { showSourceSheet = true }
    }

    /// When the payment is dated: now for today, midday for an earlier day so no time zone shifts it.
    private var paymentMoment: Date {
        guard isRecord, !Calendar.current.isDate(payDate, inSameDayAs: today) else { return Date() }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: payDate) ?? payDate
    }

    private func pay() {
        guard canPay, !isSaving else { swipeReset += 1; return }
        let source = self.source
        let paid = amount
        let left = remainingAfter
        let isFull = paid >= statement.remaining
        let usedAfter = max(card.balance - paid, 0)
        let note = noteText.trimmingCharacters(in: .whitespaces)
        let when = paymentMoment
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let source {
                    _ = try await SupabaseRepository.shared.createTransfer(
                        primaryAccountId: source.id, counterpartyAccountId: card.id, amount: paid,
                        description: "Bayar tagihan \(card.name)", note: note.isEmpty ? nil : note, date: when
                    )
                } else {
                    try await SupabaseRepository.shared.createCardPayment(
                        cardId: card.id, amount: paid, note: note.isEmpty ? nil : note, date: when
                    )
                }
                if isRecord {
                    let from = source.map { L("Dari %@", $0.name) } ?? L("Sumber lain")
                    doneLines = ("\(paid.formattedAsCurrency()) · \(from) · \(TransactionDates.dayMonth.string(from: when))",
                                 isFull ? L("Terpakai jadi %@ · status Lunas", usedAfter.formattedAsCurrency())
                                        : L("Sisa tagihan %@", left.formattedAsCurrency()))
                } else {
                    doneLines = (L("%@ dari %@", paid.formattedAsCurrency(), source?.name ?? ""),
                                 L("Sisa tagihan %@", left.formattedAsCurrency()))
                }
                BillReminderStore().clear(card: card.id, statementDate: statement.statementDate)
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                isDone = true
                try? await Task.sleep(for: .milliseconds(1500))
                onPaid?(paid, source, isFull)
                dismiss()
            } catch {
                isSaving = false
                swipeReset += 1
                errorMessage = isRecord ? L("Gagal mencatat pembayaran. Coba lagi.") : L("Gagal membayar tagihan. Coba lagi.")
            }
        }
    }
}

/// 96pt wallet card to pay from: ringed, a touch larger and checked when chosen.
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
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
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
            .scaleEffect(isSelected ? 1.03 : 1)
            .animation(.spring(duration: 0.38, bounce: 0.45), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), saldo \(account.balance.formattedAsCurrency())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
