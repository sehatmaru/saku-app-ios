import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget
    let category: Category
    let allTransactions: [Transaction]
    let accounts: [Account]
    var onAdjustBudget: ((Budget) -> Void)?
    var onUnsetBudget: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var showAllTransactions = false
    @State private var showAdjustBudget = false
    @State private var showUnsetAlert = false
    @State private var adjustAmountText = ""
    @State private var adjustAmountDigits = ""
    @State private var showAdjustConfirm = false
    @State private var pendingAmount: Double = 0

    private enum AdjustScope: String, CaseIterable {
        case thisMonth = "Hanya bulan ini"
        case ongoing = "Bulan ini dan seterusnya"
    }

    @State private var adjustScope: AdjustScope = .thisMonth
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

                    if onAdjustBudget != nil || onUnsetBudget != nil {
                        HStack(spacing: 12) {
                            if onAdjustBudget != nil {
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
                    SectionHeader(title: "Transaksi bulan ini", trailing: "\(transactions.count) transaksi")
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
                .presentationDetents([.medium])
                .presentationBackground(Color.appBackground)
        }
        .alert("Konfirmasi Perubahan", isPresented: $showAdjustConfirm) {
            Button("Batal", role: .cancel) {}
            Button("Simpan") {
                let updated = Budget(
                    id: budget.id,
                    categoryId: budget.categoryId,
                    name: budget.name,
                    amount: pendingAmount,
                    periodUnit: budget.periodUnit,
                    periodInterval: budget.periodInterval,
                    startDate: budget.startDate,
                    endDate: budget.endDate,
                    isActive: budget.isActive,
                    spent: budget.spent
                )
                onAdjustBudget?(updated)
                showAdjustBudget = false
                dismiss()
            }
        } message: {
            Text("Budget \(category.name) akan diubah menjadi \(String(Int(pendingAmount)).formattedWithThousandSeparator) untuk \"\(adjustScope.rawValue)\".")
        }
        .alert("Hapus Budget?", isPresented: $showUnsetAlert) {
            Button("Batal", role: .cancel) {}
            Button("Hapus", role: .destructive) {
                onUnsetBudget?()
                dismiss()
            }
        } message: {
            Text("Budget untuk \(category.name) akan dihapus.")
        }
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
                Button("Simpan") {
                    guard let amount = Double(adjustAmountDigits), amount > 0 else { return }
                    pendingAmount = amount
                    showAdjustConfirm = true
                }
                .font(.app(17, weight: .semibold))
                .foregroundStyle(adjustAmountDigits.isEmpty ? Color.appTextTertiary : Color.appPrimary)
                .disabled(adjustAmountDigits.isEmpty)
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

    private var scopePicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(AdjustScope.allCases), id: \.self) { scope in
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        adjustScope = scope
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: scope == .thisMonth ? "calendar.badge.clock" : "calendar.badge.plus")
                            .font(.system(size: 19))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(scope.rawValue)
                                .font(.app(16, weight: .medium))
                                .foregroundStyle(Color.appText)
                            Text(scope == .thisMonth ? "Ubah budget hanya untuk bulan berjalan" : "Terapkan untuk bulan ini dan seterusnya")
                                .font(.app(13))
                                .foregroundStyle(Color.appTextSecondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if adjustScope == scope {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.appPrimary)
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .rowSeparator()
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(adjustScope == scope ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var transactionListContent: some View {
        if transactions.isEmpty {
            EmptyMessage(icon: "tray", title: "Belum ada transaksi", message: "Pengeluaran kategori ini bulan ini muncul di sini.")
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
                            Text(showAllTransactions ? "Sembunyikan" : "Lihat Semua (\(transactions.count))")
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
                total("Terpakai", spent)
                Spacer()
                total("Budget", amount)
            }
            .padding(.top, 12)

            if showPace && amount > 0 {
                Group {
                    if remaining <= 0 {
                        Text("Budget bulan ini sudah habis.")
                    } else if daysLeft > 0 {
                        Text("Aman dipakai ")
                            + Text((remaining / Double(daysLeft)).formattedAsCurrency() + "/hari")
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

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM"
        f.locale = Locale(identifier: "id_ID")
        return f
    }()
}
