import SwiftUI

/// Pay a running installment off early (PRD Cicilan Berulang Setelah Transaksi, C8): the rest goes into the next
/// statement, or is paid now from a wallet, with an optional fee booked as a card expense. Only this payoff path exists.
struct InstallmentPayoffSheet: View {
    let item: RunningInstallment
    let card: Account
    /// Wallets the payment can come from (not the card, not an investment wallet).
    let wallets: [Account]
    let categories: [Category]
    let userId: String
    /// Called after the payoff is recorded, so the lists reload.
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode = CardInstallment.SettleMode.nextStatement
    @State private var wallet: Account?
    @State private var fee = ""
    @State private var category: Category?
    @State private var pickerKind: PickerKind?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum PickerKind: String, Identifiable { case wallet, category; var id: String { rawValue } }

    private var remaining: Double { item.remainingAmount }
    private var feeAmount: Double { Double(fee.filter(\.isNumber)) ?? 0 }
    private var billingDate: Date { CreditStatement.billing(forPurchaseOn: Date(), card: card).statement }
    private func money(_ v: Double) -> String { "Rp" + v.formattedAsDigits() }
    private func day(_ d: Date) -> String { PaydayCycle.dayMonth.string(from: d) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Lunasi cicilan lebih cepat")).font(.app(22, weight: .bold)).tracking(-0.3)
                Text(item.title).font(.app(15)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            HStack(alignment: .firstTextBaseline) {
                Text(L("Sisa cicilan")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer(minLength: 8)
                Text(money(remaining)).font(.app(20, weight: .semibold)).monospacedDigit()
            }
            .padding(.horizontal, 24).padding(.top, 16)
            Text(L("%lld dari %lld bagian belum ditagih", item.months - item.billedNow, item.months))
                .font(.app(13)).foregroundStyle(Color.appTextTertiary)
                .padding(.horizontal, 24).padding(.top, 2)

            VStack(spacing: 10) {
                option(.nextStatement, title: L("Masuk tagihan berikutnya"),
                       detail: L("Sisa %@ ditagih sekaligus pada %@. Saldo kartu tetap. Bisa dibatalkan sampai tanggal itu.", money(remaining), day(billingDate)))
                option(.paid, title: L("Langsung dibayar"),
                       detail: L("Tercatat pembayaran kartu %@ hari ini dari dompet pilihan. Saldo kartu dan dompet turun.", money(remaining)))
            }
            .padding(.horizontal, 24).padding(.top, 16)

            VStack(spacing: 0) {
                if mode == .paid { pickRow(L("Dari dompet"), wallet?.name ?? L("Pilih"), isPlaceholder: wallet == nil) { pickerKind = .wallet } }
                HStack(spacing: 12) {
                    Text(L("Biaya pelunasan")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 8)
                    Text("Rp").font(.app(16)).foregroundStyle(Color.appTextTertiary)
                    TextField(L("Opsional"), text: $fee).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .font(.app(16, weight: .medium)).monospacedDigit().frame(maxWidth: 140)
                }
                .frame(height: 50)
                if feeAmount > 0 { pickRow(L("Kategori biaya"), category?.name ?? L("Pilih"), isPlaceholder: category == nil) { pickerKind = .category } }
            }
            .padding(.horizontal, 24).padding(.top, 8)

            if let errorMessage {
                Text(errorMessage).font(.app(13)).foregroundStyle(Color.appError).padding(.horizontal, 24).padding(.top, 10)
            }
        }
        .foregroundStyle(Color.appText)
        .disabled(isSaving)
        .filterSheet {
            SmartSheetFooter(primary: L("Lunasi"), isBusy: isSaving, isEnabled: canSave, secondary: L("Batal"), onPrimary: save, onSecondary: { dismiss() })
        }
        .onAppear {
            wallet = wallet ?? wallets.first
            category = category ?? categories.first { $0.systemKey == "expense_bills_subscriptions" }
        }
        .sheet(item: $pickerKind) { kind in
            switch kind {
            case .wallet:
                WalletPickerSheet(title: L("Dari dompet"), accounts: wallets, selectedId: wallet?.id, mainId: nil, recentIds: [],
                                  onDone: { pickerKind = nil }, onPick: { wallet = $0; pickerKind = nil })
            case .category:
                CategoryPickerSheet(title: L("Kategori biaya"), categories: categories.filter { $0.type == .expense }, selectedId: category?.id,
                                    frequentIds: [], onDone: { pickerKind = nil }, onPick: { category = $0; pickerKind = nil })
            }
        }
    }

    private var canSave: Bool {
        (mode == .nextStatement || wallet != nil) && (feeAmount == 0 || category != nil)
    }

    private func option(_ value: CardInstallment.SettleMode, title: String, detail: String) -> some View {
        let on = mode == value
        return Button { withAnimation(.easeInOut(duration: 0.2)) { mode = value } } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                    Text(detail).font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(on ? Color.appPrimary : Color.appBorder)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.appFill : .clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(on ? Color.appPrimary : Color.appBorder, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pickRow(_ label: String, _ value: String, isPlaceholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                Spacer(minLength: 8)
                Text(value).font(.app(16, weight: .medium)).foregroundStyle(isPlaceholder ? Color.appTextTertiary : Color.appText).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
            }
            .frame(height: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let repo = SupabaseRepository.shared
        let today = Date()
        let dayString = CardInstallment.dateOnly.string(from: today)
        Task {
            var transferId: String?
            do {
                if mode == .paid, let wallet {
                    let transfer = try await repo.createTransfer(primaryAccountId: wallet.id, counterpartyAccountId: card.id, amount: remaining,
                                                                 description: L("Pelunasan cicilan: %@", item.title), note: nil, date: today)
                    transferId = transfer.id
                }
                try await repo.settleInstallment(id: item.id, on: dayString, mode: mode, transferId: transferId)
            } catch {
                // the payment must not stay without its installment marker: put it back
                if let transferId { try? await repo.softDeleteTransaction(id: transferId) }
                isSaving = false
                errorMessage = L("Gagal melunasi cicilan. Coba lagi.")
                return
            }
            if feeAmount > 0, let category {
                do {
                    _ = try await repo.createTransaction(accountId: card.id, categoryId: category.id, amount: feeAmount, type: .expense,
                                                         description: L("Biaya pelunasan cicilan: %@", item.title), note: nil, date: today,
                                                         userId: userId, isCreditAccount: true)
                } catch {
                    onDone()
                    NotificationCenter.default.post(name: .dataDidChange, object: nil)
                    isSaving = false
                    errorMessage = L("Cicilan sudah dilunasi, tapi biayanya gagal dicatat. Catat manual sebagai pengeluaran kartu.")
                    return
                }
            }
            onDone()
            NotificationCenter.default.post(name: .dataDidChange, object: nil)
            dismiss()
        }
    }
}
