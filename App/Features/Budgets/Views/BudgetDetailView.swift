import SwiftUI

/// Budget kategori (design "SakuQ Budget Riwayat" 1a): sisa budget hero, jatah harian card, one
/// Sesuaikan button, this period's transactions and a fixed Hapus budget button.
struct BudgetDetailView: View {
    let budget: Budget
    let category: Category
    let allTransactions: [Transaction]
    let accounts: [Account]
    /// Source of the live budget, so the page shows the new amount right after Sesuaikan.
    @ObservedObject var viewModel: BudgetListViewModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    @State private var showAllTransactions = false
    @State private var showAdjust = false
    @State private var showUnsetDialog = false
    @State private var showCancelTemporaryDialog = false
    @State private var isDeleting = false
    @State private var isCancellingTemporary = false
    @State private var failed = false
    @State private var toastText = ""
    @State private var isToastShown = false
    @State private var detailTransaction: Transaction?

    /// The budget as the list has it now (amount changes land there), else the one we were opened with.
    private var live: Budget { viewModel.budgets.first { $0.id == budget.id } ?? budget }
    private var cycle: PaydayCycle { .current }
    private var baseAmount: Double { live.baseAmount ?? live.amount }

    private var transactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        return allTransactions.filter { cycle.contains($0.date, periodOf: now, calendar: calendar) }
    }

    private var displayedTransactions: [Transaction] {
        showAllTransactions ? transactions : Array(transactions.prefix(5))
    }

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    private var barColor: Color {
        live.progress >= 1 ? .appError : live.progress >= 0.8 ? .appWarning : .appPrimary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summary
                SectionDivider()
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: L("Transaksi"), trailing: L("%lld transaksi", transactions.count))
                    transactionListContent
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) { deleteBar }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .toast(toastText, isShown: $isToastShown)
        .fullScreenCover(isPresented: $showAdjust) {
            AdjustBudgetView(budget: live, category: category, viewModel: viewModel) {
                toastText = L("Budget disesuaikan")
                isToastShown = true
            }
        }
        .confirmDialog(isPresented: $showCancelTemporaryDialog, icon: "arrow.uturn.backward",
                       title: L("Kembali ke budget awal?"),
                       message: L("Mulai periode ini, budget %@ kembali ke %@. Periode yang sudah lewat tidak berubah.",
                                  category.name, baseAmount.formattedAsCurrency()),
                       confirmTitle: L("Kembali ke budget awal"), cancelTitle: L("Tidak jadi"),
                       isBusy: isCancellingTemporary) { cancelTemporary() }
        .confirmDialog(isPresented: $showUnsetDialog, icon: "trash", destructive: true, title: L("Hapus budget ini?"),
                       message: L("Transaksi tidak ikut terhapus. Riwayat periode sebelumnya tetap tersimpan."),
                       confirmTitle: L("Hapus"), isBusy: isDeleting) { deleteBudget() }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: L("Perubahan budget belum tersimpan. Coba lagi."), confirmTitle: nil, cancelTitle: L("Tutup"))
        .sheet(item: $detailTransaction) { txn in
            TransactionDetailView(transaction: txn, categories: [category], accounts: accounts, isEditable: false)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Summary

    private var summary: some View {
        let left = live.amount - live.spent
        let daysLeft = live.daysRemaining + 1
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Sisa budget"))
                Spacer()
                Text(cycle.rangeLabel()).monospacedDigit()
            }
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)

            HeroAmount(value: left, size: .hero, color: left < 0 ? .appError : .appText,
                       isVisible: isBalanceVisible, weight: .ultraLight)
                .padding(.top, 8)

            SegmentBar(value: live.progress, color: barColor)
                .padding(.top, 20)

            HStack {
                (Text(L("Terpakai") + " ") + Text(money(live.spent)).fontWeight(.medium).foregroundStyle(Color.appText))
                Spacer()
                (Text(L("Budget") + " ") + Text(money(live.amount)).fontWeight(.medium).foregroundStyle(Color.appText))
            }
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .padding(.top, 10)

            pace(left: left, daysLeft: daysLeft)
                .padding(.top, 18)

            if let temporary = live.temporary {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 14))
                    Text(L("Sampai %@, lalu kembali ke %@", lastDay(of: temporary), baseAmount.formattedAsCurrency()))
                    Spacer(minLength: 8)
                    if isCancellingTemporary {
                        ProgressView()
                    } else {
                        Button(L("Batalkan")) { showCancelTemporaryDialog = true }
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Color.appPrimary)
                    }
                }
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 10)
            }

            Button { showAdjust = true } label: {
                Label(L("Sesuaikan"), systemImage: "slider.horizontal.3")
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(Color.appText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.appFill, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 26)
    }

    /// "Jatah Rp45.000/hari untuk 24 hari tersisa." or how far over the budget is.
    private func pace(left: Double, daysLeft: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundStyle(barColor)
            Group {
                if left < 0 {
                    Text(L("Lewat") + " ") + Text(money(-left)).fontWeight(.semibold) + Text(" " + L("dari budget periode ini."))
                } else if left == 0 {
                    Text(L("Budget periode ini sudah habis."))
                } else {
                    Text(L("Jatah") + " ") + Text(money(left / Double(max(daysLeft, 1))) + "/" + L("hari")).fontWeight(.semibold)
                        + Text(" " + L("untuk %lld hari tersisa.", daysLeft))
                }
            }
            .font(.app(15))
            .foregroundStyle(Color.appText)
            .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func lastDay(of change: BudgetAmountChange) -> String {
        let end = change.effectiveTo ?? Date()
        return PaydayCycle.dayMonth.string(from: Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end)
    }

    // MARK: Delete bar

    private var deleteBar: some View {
        Button { showUnsetDialog = true } label: {
            Label(L("Hapus budget"), systemImage: "trash")
                .font(.app(16, weight: .semibold))
                .foregroundStyle(Color(light: 0xD1343A, dark: 0xFF6B6B))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(light: 0xFDECEC, dark: 0x3A1D1F), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Color.appBackground.opacity(0), Color.appBackground], startPoint: .top, endPoint: .center)
        )
    }

    private func cancelTemporary() {
        isCancellingTemporary = true
        Task {
            let ok = await viewModel.cancelTemporary(budget: live)
            isCancellingTemporary = false
            showCancelTemporaryDialog = false
            if ok {
                toastText = L("Kembali ke budget awal")
                isToastShown = true
            } else {
                failed = true
            }
        }
    }

    private func deleteBudget() {
        isDeleting = true
        Task {
            let ok = await viewModel.removeBudget(id: budget.id)
            isDeleting = false
            showUnsetDialog = false
            if ok { dismiss() } else { failed = true }
        }
    }

    // MARK: Transactions

    @ViewBuilder
    private var transactionListContent: some View {
        if transactions.isEmpty {
            EmptyMessage(icon: "tray", title: L("Belum ada transaksi"), message: L("Pengeluaran kategori ini bulan ini muncul di sini."))
                .padding(.vertical, 32)
        } else {
            VStack(spacing: 0) {
                ForEach(displayedTransactions) { transaction in
                    Button { detailTransaction = transaction } label: {
                        TransactionRowView(transaction: transaction, categories: [category], accounts: accounts, showAccount: true)
                            .rowSeparator()
                    }
                    .buttonStyle(RowPressStyle())
                }

                if transactions.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllTransactions.toggle() }
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
}
