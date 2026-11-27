import SwiftUI

/// Cicilan 0% or Berulang for a transaction that already exists (PRD Cicilan Berulang Setelah Transaksi, C1-C7).
/// One sheet for Detail transaksi and Ubah: the same choices as Tambah transaksi, the card rules of C2 and the limits
/// of C4 (tenor and turning off only while no part has been billed; frequency and date any time).
struct TransactionPlanSheet: View {
    enum Kind { case installment, recurring }

    let kind: Kind
    let txn: Transaction
    let account: Account
    let category: Category?
    /// The existing installment or recurring bill of this transaction, if any.
    let plan: CardInstallment?
    let subscription: CardSubscription?
    let userId: String
    let onDone: () -> Void
    /// Detail transaksi holds an installment until Simpan: the sheet hands the tenor back (nil = off) instead of saving it.
    var heldMonths: Int?
    var onHold: ((Int?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var months = 6
    @State private var frequency = CardSubscription.Frequency.monthly
    @State private var nextDate = Date()
    @State private var cardTransactions: [Transaction] = []
    @State private var cardInstallments: [CardInstallment] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// The recurring bill as it stands in this sheet: set from the transaction, then kept up to date as choices are saved.
    @State private var currentBill: CardSubscription?

    private static let tenors = [3, 6, 12, 24]
    private let calendar = Calendar.current

    private var billed: Int {
        plan.map { CreditStatement.billedParts(of: $0, purchaseDate: txn.date, card: account) } ?? 0
    }
    /// C4: after a part is billed, or a payoff is chosen, the installment is fixed.
    private var isLocked: Bool { plan.map { !$0.isUntouchedByBilling(billed: billed) } ?? false }
    /// C2: the two cannot be combined on one transaction.
    private var conflict: String? {
        switch kind {
        case .installment: subscription != nil ? L("Transaksi ini sudah berulang. Matikan berulangnya dulu untuk membuatnya cicilan.") : nil
        case .recurring: plan != nil ? L("Transaksi ini sudah cicilan. Cicilan dan berulang tidak bisa digabung.") : nil
        }
    }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var startsFrom: String? { plan?.startsFrom ?? InstallmentConversion.startsFrom(purchaseDate: txn.date, card: account) }
    private var draftPlan: CardInstallment { CardInstallment(id: "new", accountId: account.id, transactionId: txn.id, months: months, startsFrom: startsFrom) }

    private var overpayment: Double {
        guard kind == .installment, plan == nil, startsFrom != nil else { return 0 }
        return InstallmentConversion.overpayment(card: account, transactions: cardTransactions, installments: cardInstallments, adding: draftPlan)
    }

    var body: some View {
        if kind == .recurring && conflict == nil { recurringSheet } else { planBody }
    }

    /// Tagihan berulang: the same sheet as Tambah transaksi. A choice is saved right away.
    private var recurringSheet: some View {
        RepeatChoiceSheet(selected: currentBill?.isActive == true ? currentBill?.frequency : nil, amount: txn.amount, accountName: account.name,
                          date: { RepeatChoiceSheet.nextDate(from: txn.date, $0) },
                          isBusy: isSaving,
                          onSelect: { choose($0) }, onDone: { dismiss() })
            .task { currentBill = subscription }
    }

    private func choose(_ value: CardSubscription.Frequency?) {
        guard !isSaving else { return }
        if value == nil && currentBill?.isActive != true { return }
        if let value, currentBill?.isActive == true, currentBill?.frequency == value { return }
        isSaving = true
        let repo = SupabaseRepository.shared
        Task {
            do {
                if let value {
                    await NotificationManager.shared.requestPermissionIfNeeded()
                    let date = Self.dayString(RepeatChoiceSheet.nextDate(from: txn.date, value))
                    let bill: CardSubscription
                    if let existing = currentBill {
                        bill = try await repo.updateSubscription(id: existing.id, name: existing.name, amount: existing.amount, frequency: value,
                                                                 nextBillingDate: date, isActive: true, categoryId: existing.categoryId, note: existing.note)
                    } else {
                        bill = try await repo.createSubscription(accountId: account.id, name: txn.displayNote ?? category?.name ?? "Tagihan", amount: txn.amount,
                                                                 frequency: value, nextBillingDate: date, categoryId: category?.id, note: nil, sourceTransactionId: txn.id)
                    }
                    await NotificationManager.shared.schedule(for: bill)
                    currentBill = bill
                } else if let existing = currentBill {
                    currentBill = try await repo.updateSubscription(id: existing.id, name: existing.name, amount: existing.amount, frequency: existing.frequency,
                                                                    nextBillingDate: existing.nextBillingDate, isActive: false, categoryId: existing.categoryId, note: existing.note)
                    await NotificationManager.shared.cancel(for: existing)
                }
                isSaving = false
                onDone()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
            } catch { isSaving = false }
        }
    }

    private var planBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .installment ? L("Cicilan 0%") : L("Tagihan berulang")).font(.app(22, weight: .bold)).tracking(-0.3)
                Text("Rp" + txn.amount.formattedAsDigits() + " · " + (txn.displayNote ?? category?.name ?? account.name))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            if let conflict {
                note(conflict, icon: "exclamationmark.circle")
            } else if kind == .installment {
                installmentBody
            } else {
                recurringBody
            }
            if let errorMessage {
                Text(errorMessage).font(.app(13)).foregroundStyle(Color.appError).padding(.horizontal, 24).padding(.top, 10)
            }
        }
        .foregroundStyle(Color.appText)
        .disabled(isSaving)
        .filterSheet { footer }
        .task { await load() }
    }

    // MARK: Installment

    @ViewBuilder private var installmentBody: some View {
        if isLocked {
            note(settledText ?? L("%lld dari %lld bagian sudah ditagih, jadi cicilan tidak bisa dimatikan atau diganti tenornya. Untuk menyelesaikannya lebih cepat, pakai Lunasi lebih cepat di Cicilan berjalan.", billed, plan?.months ?? 0),
                 icon: "lock")
        } else {
            tenorChips
            let part = CardInstallment.part(1, of: txn.amount, months: months)
            let first = CreditStatement.partBillings(of: draftPlan, purchaseDate: txn.date, card: account).first
            Text(L("Rp%@ per bulan, bagian pertama ditagih %@.", part.formattedAsDigits(), first.map { PaydayCycle.dayMonth.string(from: $0) } ?? "-"))
                .font(.app(15)).foregroundStyle(Color.appBody).padding(.horizontal, 24).padding(.top, 14)
            if let startsFrom, plan == nil, let day = CardInstallment.dateOnly.date(from: startsFrom) {
                note(L("Transaksi ini sudah masuk tagihan yang tercetak. Cicilan dihitung mulai %@; tagihan yang sudah tercetak tidak ditulis ulang, sisa yang harus dibayar berkurang Rp%@.",
                       PaydayCycle.dayMonth.string(from: day), txn.amount.formattedAsDigits()), icon: "info.circle")
            }
            if overpayment > 0 {
                note(L("Tagihan itu sudah dibayar lunas. Pembayarannya menjadi kelebihan bayar Rp%@ yang memotong tagihan cicilan berikutnya.", overpayment.formattedAsDigits()),
                     icon: "exclamationmark.triangle")
            }
        }
    }

    private var settledText: String? {
        guard let s = plan?.settlement else { return nil }
        return s.mode == .paid ? L("Cicilan ini sudah dilunasi dari dompet pada %@.", PaydayCycle.dayMonth.string(from: s.day))
                               : L("Cicilan ini dilunasi dan masuk tagihan berikutnya. Batalkan pelunasannya di Cicilan berjalan.")
    }

    private var tenorChips: some View {
        HStack(spacing: 8) {
            ForEach(Self.tenors, id: \.self) { value in
                let on = months == value
                Button { months = value } label: {
                    Text(L("%lld bulan", value)).font(.app(14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Color.appBackground : Color.appText)
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(on ? Color.appText : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? .clear : Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16)
    }

    // MARK: Recurring

    @ViewBuilder private var recurringBody: some View {
        HStack(spacing: 8) {
            ForEach([(CardSubscription.Frequency.monthly, L("Tiap bulan")), (.yearly, L("Tiap tahun"))], id: \.0) { value, title in
                let on = frequency == value
                Button { frequency = value } label: {
                    Text(title).font(.app(15, weight: .medium))
                        .foregroundStyle(on ? Color.appBackground : Color.appText)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(on ? Color.appText : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? .clear : Color.appBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16)
        DatePicker(L("Tagihan berikutnya"), selection: $nextDate, in: today..., displayedComponents: .date)
            .font(.app(15)).padding(.horizontal, 24).padding(.top, 10)
        note(L("Transaksi ini tidak dicatat ulang. Tagihan berulang dicatat otomatis mulai tanggal itu, tanpa tagihan mundur."), icon: "info.circle")
    }

    private func note(_ text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.appPrimary).frame(width: 24)
            Text(text).font(.app(15)).lineSpacing(2).foregroundStyle(Color.appBody).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24).padding(.top, 16)
    }

    // MARK: Actions

    @ViewBuilder private var footer: some View {
        if conflict != nil || (kind == .installment && isLocked) {
            SmartSheetFooter(primary: L("Mengerti"), onPrimary: { dismiss() })
        } else if (kind == .installment && (plan != nil || heldMonths != nil)) || (kind == .recurring && subscription != nil) {
            VStack(spacing: 4) {
                SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, onPrimary: save)
                Button(kind == .installment ? L("Matikan cicilan") : L("Matikan berulang"), role: .destructive, action: turnOff)
                    .font(.app(15, weight: .medium)).frame(height: 40)
            }
        } else {
            SmartSheetFooter(primary: L("Simpan"), isBusy: isSaving, secondary: L("Batal"), onPrimary: save, onSecondary: { dismiss() })
        }
    }

    private func load() async {
        if let plan { months = plan.months }
        if let heldMonths, heldMonths > 0 { months = heldMonths }
        if let subscription {
            frequency = subscription.frequency
            nextDate = subscription.nextBillingDateAsDate.map { max($0, today) } ?? today
        } else {
            nextDate = defaultNextDate(frequency)
        }
        if kind == .installment, plan == nil {
            cardTransactions = (try? await SupabaseRepository.shared.fetchTransactions(accountId: account.id, userId: userId)) ?? []
            cardInstallments = (try? await SupabaseRepository.shared.fetchInstallments(accountIds: [account.id])) ?? []
        }
    }

    /// A period on from the transaction, and never a day that is already past.
    private func defaultNextDate(_ frequency: CardSubscription.Frequency) -> Date {
        let component: Calendar.Component = frequency == .yearly ? .year : .month
        var next = calendar.startOfDay(for: txn.date)
        repeat { next = calendar.date(byAdding: component, value: 1, to: next) ?? next } while next < today
        return next
    }

    private func finish() {
        onDone()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        dismiss()
    }

    private func fail(_ error: Error) {
        isSaving = false
        errorMessage = L("Gagal menyimpan. Coba lagi.")
    }

    private func save() {
        guard !isSaving else { return }
        if kind == .installment, let onHold { onHold(months); dismiss(); return }
        isSaving = true
        errorMessage = nil
        let repo = SupabaseRepository.shared
        Task {
            do {
                switch kind {
                case .installment:
                    if let plan { if months != plan.months { try await repo.updateInstallmentMonths(id: plan.id, months: months) } }
                    else { try await repo.createInstallment(accountId: account.id, transactionId: txn.id, months: months, startsFrom: startsFrom) }
                case .recurring:
                    await NotificationManager.shared.requestPermissionIfNeeded()
                    let name = txn.displayNote ?? category?.name ?? "Tagihan"
                    let date = Self.dayString(nextDate)
                    let bill: CardSubscription
                    if let subscription {
                        bill = try await repo.updateSubscription(id: subscription.id, name: subscription.name, amount: subscription.amount, frequency: frequency,
                                                                 nextBillingDate: date, isActive: true, categoryId: subscription.categoryId, note: subscription.note)
                    } else {
                        bill = try await repo.createSubscription(accountId: account.id, name: name, amount: txn.amount, frequency: frequency, nextBillingDate: date,
                                                                 categoryId: category?.id, note: nil, sourceTransactionId: txn.id)
                    }
                    await NotificationManager.shared.schedule(for: bill)
                }
                finish()
            } catch { fail(error) }
        }
    }

    private func turnOff() {
        guard !isSaving else { return }
        if kind == .installment, let onHold { onHold(nil); dismiss(); return }
        isSaving = true
        let repo = SupabaseRepository.shared
        Task {
            do {
                if kind == .installment, let plan { try await repo.deleteInstallment(id: plan.id) }
                if kind == .recurring, let subscription {
                    _ = try await repo.updateSubscription(id: subscription.id, name: subscription.name, amount: subscription.amount, frequency: subscription.frequency,
                                                          nextBillingDate: subscription.nextBillingDate, isActive: false, categoryId: subscription.categoryId, note: subscription.note)
                    await NotificationManager.shared.cancel(for: subscription)
                }
                finish()
            } catch { fail(error) }
        }
    }

    private static func dayString(_ date: Date) -> String { CardInstallment.dateOnly.string(from: date) }
}
