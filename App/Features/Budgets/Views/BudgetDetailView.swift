import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget
    let category: Category
    let allTransactions: [Transaction]
    let accounts: [Account]
    /// Saves a new amount; false when it could not be saved.
    var onSaveAmount: ((Double, BudgetAmountDuration) async -> Bool)?
    var onCancelTemporary: (() async -> Bool)?
    var onUnsetBudget: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss

    @State private var showAllTransactions = false
    @State private var showAdjustBudget = false
    @State private var showUnsetAlert = false
    @State private var adjustAmountText = ""
    @State private var adjustAmountDigits = ""
    @State private var showOverspendAlert = false
    @State private var showReplaceAlert = false
    @State private var showCancelTemporaryAlert = false
    @State private var isSavingAmount = false
    @State private var saveFailed = false
    @State private var isCancellingTemporary = false
    @State private var isDeleting = false
    @State private var deleteFailed = false
    @State private var pendingAmount: Double = 0

    private enum AdjustScope: CaseIterable {
        case forever, thisOnly, several
    }

    @State private var adjustScope: AdjustScope = .forever
    @State private var periodCount = 3
    @State private var detailTransaction: Transaction?

    private var transactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        return allTransactions.filter { PaydayCycle.current.contains($0.date, periodOf: now, calendar: calendar) }
    }

    private var displayedTransactions: [Transaction] {
        showAllTransactions ? transactions : Array(transactions.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BudgetSummary(amount: budget.amount, spent: budget.spent, month: Date(), showPace: true)

                    if let temporary = budget.temporary {
                        temporaryNote(temporary)
                    }

                    if onSaveAmount != nil || onUnsetBudget != nil {
                        HStack(spacing: 12) {
                            if onSaveAmount != nil {
                                Button {
                                    adjustAmountText = ""
                                    adjustAmountDigits = ""
                                    showAdjustBudget = true
                                } label: {
                                    Label("Sesuaikan", systemImage: "slider.horizontal.3")
                                        .font(.app(15, weight: .medium))
                                        .foregroundStyle(Color.appText)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(Color.appFill, in: Capsule())
                                }
                                .buttonStyle(PressScaleStyle())
                            }

                            if onUnsetBudget != nil {
                                Button(role: .destructive) {
                                    showUnsetAlert = true
                                } label: {
                                    Label("Hapus budget", systemImage: "xmark")
                                        .font(.app(15, weight: .medium))
                                        .foregroundStyle(Color.appError)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .overlay(Capsule().strokeBorder(Color.appBorder))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(PressScaleStyle())
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 32)

                SectionDivider()

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: L("Transaksi bulan ini"), trailing: L("%lld transaksi", transactions.count))
                    transactionListContent
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .background(Color.appBackground)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdjustBudget) {
            adjustBudgetSheet
                .confirmDialog(isPresented: $showOverspendAlert, icon: "exclamationmark.triangle",
                               title: L("Budget langsung lewat batas"),
                               message: L("Pengeluaranmu periode ini sudah %@, lebih besar dari %@. Budget akan langsung berstatus lewat batas. Lanjutkan?",
                                          budget.spent.formattedAsCurrency(), pendingAmount.formattedAsCurrency()),
                               confirmTitle: L("Lanjutkan")) {
                    showOverspendAlert = false
                    proceedAfterOverspend()
                }
                .confirmDialog(isPresented: $showReplaceAlert, icon: "arrow.triangle.2.circlepath",
                               title: L("Ganti perubahan sementara?"),
                               message: budget.temporary.map {
                                   L("Kamu sudah punya budget sementara %@ sampai %@. Yang baru akan menggantikannya.",
                                     $0.amount.formattedAsCurrency(), lastDay(of: $0))
                               } ?? "",
                               confirmTitle: L("Ganti"), cancelTitle: L("Tidak jadi")) {
                    showReplaceAlert = false
                    saveAmount()
                }
                .confirmDialog(isPresented: $saveFailed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                               message: L("Perubahan budget belum tersimpan. Coba lagi."), confirmTitle: nil,
                               cancelTitle: L("Tutup"))
                .presentationDetents([.large])
                .presentationBackground(Color.appBackground)
        }
        .confirmDialog(isPresented: $showCancelTemporaryAlert, icon: "arrow.uturn.backward",
                       title: L("Kembali ke budget awal?"),
                       message: L("Mulai periode ini, budget %@ kembali ke %@. Periode yang sudah lewat tidak berubah.",
                                  category.name, (budget.baseAmount ?? budget.amount).formattedAsCurrency()),
                       confirmTitle: L("Kembali ke budget awal"), cancelTitle: L("Tidak jadi"),
                       isBusy: isCancellingTemporary) { cancelTemporary() }
        .confirmDialog(isPresented: $showUnsetAlert, icon: "trash", destructive: true, title: L("Hapus Budget?"),
                       message: L("Budget untuk %@ akan dihapus.", category.name),
                       confirmTitle: L("Hapus"), isBusy: isDeleting) { deleteBudget() }
        .confirmDialog(isPresented: $deleteFailed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: L("Perubahan budget belum tersimpan. Coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(
                transaction: txn,
                categories: [category],
                accounts: accounts,
                isEditable: false
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var adjustBudgetSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Batal") {
                    showAdjustBudget = false
                }
                .font(.app(17))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 70, alignment: .leading)
                Spacer()
                Text("Sesuaikan Budget \(category.name)")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button {
                    guard let amount = Double(adjustAmountDigits), amount > 0 else { return }
                    pendingAmount = amount
                    if amount < budget.spent {
                        showOverspendAlert = true
                    } else {
                        proceedAfterOverspend()
                    }
                } label: {
                    if isSavingAmount { ProgressView() } else { Text("Simpan") }
                }
                .font(.app(17, weight: .semibold))
                .foregroundStyle(adjustAmountDigits.isEmpty ? Color.appTextTertiary : Color.appPrimary)
                .disabled(adjustAmountDigits.isEmpty || isSavingAmount)
                .frame(width: 70, alignment: .trailing)
            }
            .frame(height: 44)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Text("Rp")
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                TextField("\(String(Int(budget.amount)).formattedWithThousandSeparator)", text: $adjustAmountText)
                    .font(.app(17, weight: .medium))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            scopePicker
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()
        }
        .background(Color.appBackground)
        .onChange(of: adjustAmountText) { _, newValue in
            let digits = String(newValue.filter { $0.isWholeNumber })
            let formatted = digits.formattedWithThousandSeparator
            if formatted != newValue {
                adjustAmountText = formatted
            }
            adjustAmountDigits = digits
        }
    }

    private var cycle: PaydayCycle { .current }
    private var currentPeriod: DateInterval { cycle.period(containing: Date()) }
    private var baseAmount: Double { budget.baseAmount ?? budget.amount }

    private var count: Int {
        switch adjustScope {
        case .forever: return 0
        case .thisOnly: return 1
        case .several: return periodCount
        }
    }

    /// Last day of the Nth period from now, N included the running one.
    private func lastDay(ofPeriods n: Int) -> String {
        let end = cycle.period(offset: n - 1).end
        return PaydayCycle.dayMonth.string(from: Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    private func lastDay(of change: BudgetAmountChange) -> String {
        let end = change.effectiveTo ?? Date()
        return PaydayCycle.dayMonth.string(from: Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    private func subtitle(_ scope: AdjustScope) -> String {
        switch scope {
        case .forever:
            return L("Nominal baru dipakai terus mulai periode ini. Periode lama tidak berubah.")
        case .thisOnly:
            return L("Hanya untuk %@ - %@. Setelah itu kembali ke %@.", PaydayCycle.dayMonth.string(from: currentPeriod.start),
                     lastDay(ofPeriods: 1), baseAmount.formattedAsCurrency())
        case .several:
            return L("Pilih berapa periode. Setelah selesai, otomatis kembali ke %@.", baseAmount.formattedAsCurrency())
        }
    }

    private func title(_ scope: AdjustScope) -> String {
        switch scope {
        case .forever: return L("Selamanya")
        case .thisOnly: return L("Periode ini saja")
        case .several: return L("Beberapa periode")
        }
    }

    /// What saving will do, in the user's own amounts and dates.
    private var summary: String? {
        guard let amount = Double(adjustAmountDigits), amount > 0 else { return nil }
        let start = PaydayCycle.dayMonth.string(from: currentPeriod.start)
        if adjustScope == .forever {
            return L("Mulai %@, budget %@ jadi %@ setiap periode. Periode sebelumnya tetap seperti dulu.",
                     start, category.name, amount.formattedAsCurrency())
        }
        let end = cycle.period(offset: count - 1).end
        return L("%@ dipakai dari %@ sampai %@ (%lld periode). Mulai %@ kembali ke %@. Budget awalmu tidak berubah.",
                 amount.formattedAsCurrency(), start, lastDay(ofPeriods: count), count,
                 PaydayCycle.dayMonth.string(from: end), baseAmount.formattedAsCurrency())
    }

    private func proceedAfterOverspend() {
        if budget.temporary != nil && adjustScope != .forever {
            showReplaceAlert = true
        } else {
            saveAmount()
        }
    }

    private func saveAmount() {
        guard let onSaveAmount else { return }
        isSavingAmount = true
        let duration: BudgetAmountDuration = adjustScope == .forever ? .forever : .periods(count)
        Task {
            let ok = await onSaveAmount(pendingAmount, duration)
            isSavingAmount = false
            if ok {
                showAdjustBudget = false
                dismiss()
            } else {
                saveFailed = true
            }
        }
    }

    private func cancelTemporary() {
        guard let onCancelTemporary else { return }
        isCancellingTemporary = true
        Task {
            let ok = await onCancelTemporary()
            isCancellingTemporary = false
            showCancelTemporaryAlert = false
            if ok { dismiss() } else { deleteFailed = true }
        }
    }

    private func deleteBudget() {
        guard let onUnsetBudget else { return }
        isDeleting = true
        Task {
            let ok = await onUnsetBudget()
            isDeleting = false
            showUnsetAlert = false
            if ok { dismiss() } else { deleteFailed = true }
        }
    }

    private func temporaryNote(_ temporary: BudgetAmountChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Sementara %@ sampai %@, lalu kembali %@", temporary.amount.formattedAsCurrency(),
                   lastDay(of: temporary), baseAmount.formattedAsCurrency()))
                .font(.app(14))
                .foregroundStyle(Color.appTextSecondary)
            if onCancelTemporary != nil {
                Button(L("Batalkan perubahan sementara")) { showCancelTemporaryAlert = true }
                    .font(.app(14, weight: .semibold))
                    .foregroundStyle(Color.appPrimary)
            }
        }
        .padding(.top, 14)
    }

    private var scopePicker: some View {
        VStack(spacing: 0) {
            Text(L("Berlaku untuk berapa lama?"))
                .font(.app(14, weight: .semibold))
                .foregroundStyle(Color.appTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            ForEach(AdjustScope.allCases, id: \.self) { scope in
                Button {
                    withAnimation(.spring(duration: 0.25)) { adjustScope = scope }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(scope))
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Color.appText)
                            Text(subtitle(scope))
                                .font(.app(13))
                                .foregroundStyle(Color.appTextSecondary)
                                .lineLimit(3)
                        }
                        Spacer()
                        if adjustScope == scope {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .rowSeparator()
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(adjustScope == scope ? .isSelected : [])
            }
            if adjustScope == .several {
                Stepper(L("%lld periode", periodCount), value: $periodCount, in: 2...12)
                    .font(.app(15))
                    .padding(.top, 8)
            }
            if let summary {
                Text(summary)
                    .font(.app(13))
                    .foregroundStyle(Color.appBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var transactionListContent: some View {
        if transactions.isEmpty {
            EmptyMessage(icon: "tray", title: L("Belum ada transaksi"), message: L("Pengeluaran kategori ini bulan ini muncul di sini."))
                .padding(.vertical, 32)
        } else {
            VStack(spacing: 0) {
                ForEach(displayedTransactions) { transaction in
                    Button { detailTransaction = transaction } label: {
                        transactionRow(transaction)
                            .rowSeparator()
                    }
                    .buttonStyle(RowPressStyle())
                }

                if transactions.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllTransactions.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showAllTransactions ? L("Sembunyikan") : L("Lihat Semua (%lld)", transactions.count))
                                .font(.app(15, weight: .medium))
                            Image(systemName: showAllTransactions ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.appPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
        }
    }

    private func transactionRow(_ transaction: Transaction) -> some View {
        TransactionRowView(transaction: transaction, categories: [category], accounts: accounts, showAccount: true)
    }
}

// MARK: - Summary

/// "Sisa budget" hero, segment bar and totals, as on the Budget tab.
fileprivate struct BudgetSummary: View {
    let amount: Double
    let spent: Double
    let month: Date
    /// The per-day "Aman dipakai" line; only meaningful for the running month.
    var showPace = false

    private var remaining: Double { amount - spent }
    private var progress: Double { amount > 0 ? spent / amount : 0 }
    private var remainingPct: Double { progress >= 1 ? 0 : (1 - progress) * 100 }

    private var barColor: Color {
        remainingPct <= 0 ? .appError : remainingPct <= 20 ? .appWarning : .appPrimary
    }

    var body: some View {
        let calendar = Calendar.current
        let daysLeft = (calendar.range(of: .day, in: .month, for: month)?.count ?? 30) - calendar.component(.day, from: month)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sisa budget \(Self.monthFormatter.string(from: month))")
                Spacer()
                Text("\(Int(remainingPct))%").monospacedDigit()
            }
            .font(.app(15))
            .foregroundStyle(remaining < 0 ? Color.appError : Color.appTextSecondary)

            HeroAmount(value: max(0, remaining), size: .hero, weight: .ultraLight)
                .padding(.top, 8)

            SegmentBar(value: progress, color: barColor, height: 12)
                .padding(.top, 24)

            HStack {
                total(L("Terpakai"), spent)
                Spacer()
                total(L("Budget"), amount)
            }
            .padding(.top, 12)

            if showPace && amount > 0 {
                Group {
                    if remaining <= 0 {
                        Text("Budget bulan ini sudah habis.")
                    } else if daysLeft > 0 {
                        Text("Jatah ")
                            + Text(L("%@/hari", (remaining / Double(daysLeft)).formattedAsCurrency()))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.appText)
                            + Text(" untuk \(daysLeft) hari tersisa.")
                    } else {
                        Text("Hari terakhir: sisa ")
                            + Text(remaining.formattedAsCurrency()).fontWeight(.semibold).foregroundStyle(Color.appText)
                            + Text(" bisa dipakai hari ini.")
                    }
                }
                .font(.app(15))
                .lineSpacing(3)
                .foregroundStyle(Color.appBody)
                .padding(.top, 18)
            }
        }
    }

    private func total(_ label: String, _ value: Double) -> some View {
        (Text(label + " ").foregroundStyle(Color.appTextSecondary)
         + Text(value.abbreviatedRupiah())
            .fontWeight(.medium)
            .foregroundStyle(Color.appText))
            .font(.app(15))
            .monospacedDigit()
    }

    private static var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = AppLanguage.locale
        return f
    }
}
