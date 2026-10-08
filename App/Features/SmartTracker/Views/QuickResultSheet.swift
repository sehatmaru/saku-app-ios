import SwiftUI

/// The result of one sentence (design 1c): what Saku understood, with the wallet and the date still
/// changeable, and Simpan right here or "Simpan nanti" to Perlu dicek.
struct QuickResultSheet: View {
    @State var draft: Draft
    let userId: String
    var onSaved: (String) -> Void
    var onSaveLater: (Draft) -> Void
    var onRedo: () -> Void
    @ObservedObject private var store = DraftStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var failed = false
    @State private var pickedWallet = false
    @State private var pickedDate = false
    @State private var showsDatePicker = false
    @State private var contentHeight: CGFloat = 400

    private var sentenceNote: String { draft.source == .voice ? L("Dari suaramu") : L("Dari ketikanmu") }
    private var wallet: Account? { store.accounts.first { $0.id == draft.accountId } }
    private var category: Category? { store.categories.first { $0.id == draft.categoryId } }
    private var isIncome: Bool { draft.kind == .income }

    private var wallets: [Account] { store.accounts.filter { $0.isActive && $0.type != .investment } }
    private var categories: [Category] {
        store.categories.filter { $0.type == (isIncome ? .income : .expense) && !CategoryCatalog.isSystem($0) }
    }

    private var dateOptions: [(String, Date)] {
        let cal = Calendar.current
        let today = Date()
        return [(L("Hari ini"), today), (L("Kemarin"), cal.date(byAdding: .day, value: -1, to: today) ?? today),
                (L("2 hari lalu"), cal.date(byAdding: .day, value: -2, to: today) ?? today)]
    }

    private var dateLabel: String {
        let cal = Calendar.current
        let day = DateFormatter.shortDay.string(from: draft.date)
        if cal.isDateInToday(draft.date) { return L("Hari ini") + ", " + day }
        if cal.isDateInYesterday(draft.date) { return L("Kemarin") + ", " + day }
        return day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(sentenceNote, systemImage: "sparkles")
                    .font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                Button {
                    dismiss()
                    onSaveLater(draft)
                } label: {
                    Label(L("Simpan nanti"), systemImage: "tray")
                        .font(.app(13, weight: .semibold)).foregroundStyle(Color.appText)
                        .padding(.horizontal, 12).frame(height: 30).background(Color.stChip, in: Capsule())
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Circle().fill(Color(light: isIncome ? 0xE6F3EC : 0xFDECEC, dark: isIncome ? 0x1E3A2C : 0x3A1D1F)).frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: category?.icon ?? "tag").font(.system(size: 20))
                            .foregroundStyle(isIncome ? Color.stGreen : Color.stDangerText)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.title).font(.app(17, weight: .semibold)).lineLimit(1)
                    Menu {
                        ForEach(categories) { c in Button(c.name) { draft.categoryId = c.id; draft.fromMemory = false } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(category?.name ?? L("Pilih kategori"))
                                .foregroundStyle(category == nil ? Color.appWarning : Color.appTextSecondary)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.appTextTertiary)
                        }
                        .font(.app(13))
                    }
                }
                Spacer()
                Text((isIncome ? "" : "−") + "Rp" + (draft.amount ?? 0).formattedAsDigits())
                    .font(.app(30, weight: .light)).tracking(-1).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            VStack(spacing: 0) {
                row(title: L("Dompet"), note: pickedWallet ? L("Diganti") : (draft.accountId == nil ? nil : L("Dari kalimatmu")),
                    value: wallet?.name ?? L("Belum dipilih"), warn: wallet == nil) {
                    ForEach(wallets) { w in Button(w.name) { draft.accountId = w.id; pickedWallet = true } }
                }
                Divider().padding(.horizontal, 14)
                row(title: L("Tanggal"), note: pickedDate ? L("Diganti") : nil, value: dateLabel, warn: false) {
                    ForEach(dateOptions, id: \.0) { option in Button(option.0) { draft.date = option.1; pickedDate = true } }
                    Button(L("Pilih tanggal…")) { showsDatePicker = true }
                }
            }
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 20).padding(.top, 18)

            if duplicate != nil {
                Label(duplicate ?? "", systemImage: "doc.on.doc")
                    .font(.app(12)).foregroundStyle(Color.appWarning).padding(.horizontal, 22).padding(.top, 10)
            }

            HStack(spacing: 10) {
                Button { dismiss(); onRedo() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.appText)
                        .frame(width: 54, height: 54).background(Color.stChip, in: Circle())
                }
                .accessibilityLabel(L("Ulang"))
                Button(action: save) {
                    ZStack {
                        if isSaving { ProgressView().tint(Color.appBackground) } else {
                            Label(L("Simpan"), systemImage: "checkmark").font(.app(17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(draft.isComplete ? Color.appText : Color.appTextTertiary, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .disabled(isSaving)
            }
            .padding(.horizontal, 20).padding(.top, 22)
        }
        .padding(.top, 22).padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .presentationDetents([.height(contentHeight + 28)])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showsDatePicker) {
            DatePicker("", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .presentationDetents([.medium]).presentationBackground(Color.appBackground)
                .onDisappear { pickedDate = true }
        }
        .confirmDialog(isPresented: $failed, icon: "exclamationmark.triangle", title: L("Gagal menyimpan"),
                       message: L("Draf belum tersimpan. Coba lagi, atau pilih Simpan nanti."), confirmTitle: nil, cancelTitle: L("Tutup"))
    }

    private var duplicate: String? { store.duplicateNote(for: draft) }

    private func row<Items: View>(title: String, note: String?, value: String, warn: Bool,
                                  @ViewBuilder items: () -> Items) -> some View {
        Menu { items() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    if let note { Text(note).font(.app(12)).foregroundStyle(Color.stGreen) }
                }
                Spacer()
                HStack(spacing: 7) {
                    Text(value).font(.app(16, weight: .medium)).foregroundStyle(warn ? Color.appWarning : Color.appText)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(Color.appTextTertiary)
                }
            }
            .padding(.horizontal, 14).frame(minHeight: 54)
            .contentShape(Rectangle())
        }
    }

    private func save() {
        guard draft.isComplete else {
            // not complete (no wallet or category): it can be finished in Perlu dicek
            dismiss()
            onSaveLater(draft)
            return
        }
        isSaving = true
        Task {
            do {
                try await store.saveImmediately(draft, userId: userId)
                isSaving = false
                dismiss()
                onSaved("\(draft.title) \(isIncome ? "+" : "−")Rp\((draft.amount ?? 0).formattedAsDigits()) " + L("tersimpan"))
            } catch {
                isSaving = false
                failed = true
            }
        }
    }
}
