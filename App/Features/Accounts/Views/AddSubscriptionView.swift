import SwiftUI

/// "Tambah tagihan" sheet (design 1b): amount, name, category chips, billing day, frequency and a numpad.
struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let account: Account
    let existing: CardSubscription?
    let onSave: () -> Void

    @State private var amount = 0
    @State private var nameText = ""
    @State private var selectedCategory: Category?
    @State private var isCategoryOpen = false
    @State private var selectedFrequency: CardSubscription.Frequency = .monthly
    @State private var billingDay = Calendar.current.component(.day, from: Date())
    @State private var bump = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @FocusState private var isNameFocused: Bool

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    init(categories: [Category], account: Account, existing: CardSubscription? = nil, onSave: @escaping () -> Void) {
        self.categories = categories
        self.account = account
        self.existing = existing
        self.onSave = onSave
    }

    private var canSave: Bool {
        amount > 0 && !nameText.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    private var frequencyText: String { selectedFrequency == .monthly ? "tiap bulan" : "tiap tahun" }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                    VStack(spacing: 0) {
                        nameRow
                        categoryRow
                        categoryChips
                        dayRow
                        frequencyRow
                        if existing != nil { manageRow }
                    }
                    .overlay(alignment: .top) { Rectangle().fill(Color.appSeparator).frame(height: 1) }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.app(13))
                            .foregroundStyle(Color.appError)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            AmountPad(color: .appPrimary, isEnabled: canSave, isSaving: isSaving, onPress: press, onSave: save)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground)
        .presentationBackground(Color.appBackground)
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
        .confirmationDialog("Hapus tagihan ini?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Hapus tagihan", role: .destructive) { delete() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Tagihan berikutnya tidak akan dicatat lagi.")
        }
    }

    // MARK: Header

    private var topBar: some View {
        HStack {
            Button("Batal") { dismiss() }
                .font(.app(17))
                .foregroundStyle(Color.appPrimary)
            Spacer()
        }
        .overlay {
            Text(existing != nil ? "Ubah tagihan" : "Tambah tagihan")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 13)
    }

    // MARK: Amount

    private var amountSection: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text("Rp")
                    .font(.app(20))
                    .foregroundStyle(Color.appTextSecondary)
                    .padding(.top, 7)
                Text(Double(amount).formattedAsDigits())
                    .font(.app(48, weight: .light))
                    .tracking(-1.8)
                    .foregroundStyle(amount > 0 ? Color.appText : Color.appTextTertiary)
                    .animation(.easeInOut(duration: 0.2), value: amount > 0)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .scaleEffect(bump ? 1.04 : 1)
            .animation(.easeOut(duration: 0.14), value: bump)
            Text("Ditagih ke \(account.name) \(frequencyText)")
                .font(.app(13))
                .foregroundStyle(Color.appTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .accessibilityElement(children: .combine)
    }

    // MARK: Rows

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .lineLimit(1)
            .frame(width: 100, alignment: .leading)
    }

    private var nameRow: some View {
        HStack(spacing: 12) {
            label("Nama")
            TextField("Contoh: Netflix", text: $nameText)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onChange(of: nameText) { _, new in
                    if new.count > 40 { nameText = String(new.prefix(40)) }
                }
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
    }

    private var categoryRow: some View {
        Button {
            isNameFocused = false
            withAnimation(.easeInOut(duration: 0.3)) { isCategoryOpen.toggle() }
        } label: {
            HStack(spacing: 12) {
                label("Kategori")
                HStack(spacing: 8) {
                    Image(systemName: selectedCategory?.icon ?? "tag")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appTextSecondary)
                    Text(selectedCategory?.name ?? "Pilih")
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(selectedCategory == nil ? Color.appTextSecondary : Color.appText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
                    .rotationEffect(.degrees(isCategoryOpen ? 180 : 0))
            }
            .frame(height: 52)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .rowSeparator()
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityValue(selectedCategory?.name ?? "Belum dipilih")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(expenseCategories) { category in
                    let isOn = category.id == selectedCategory?.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = category }
                        Task {
                            try? await Task.sleep(for: .milliseconds(240))
                            withAnimation(.easeInOut(duration: 0.3)) { isCategoryOpen = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon ?? "tag").font(.system(size: 14))
                            Text(category.name).font(.app(14, weight: .medium))
                        }
                        .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                        .padding(.leading, 11)
                        .padding(.trailing, 14)
                        .frame(height: 36)
                        .background(isOn ? Color.appText : Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .frame(height: isCategoryOpen ? 56 : 0, alignment: .top)
        .opacity(isCategoryOpen ? 1 : 0)
        .clipped()
        .rowSeparator()
        .allowsHitTesting(isCategoryOpen)
    }

    private var dayRow: some View {
        HStack(spacing: 12) {
            label("Tanggal tagih")
            Menu {
                Picker("Tanggal tagih", selection: $billingDay) {
                    ForEach(1...31, id: \.self) { Text("Tanggal \($0)").tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Tanggal \(billingDay)")
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                    Text("· " + TransactionDates.dayMonth.string(from: nextBillingDate))
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .monospacedDigit()
                .contentShape(Rectangle())
            }
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
    }

    private var frequencyRow: some View {
        HStack(spacing: 12) {
            label("Frekuensi")
            HStack(spacing: 8) {
                frequencyChip("Bulanan", .monthly)
                frequencyChip("Tahunan", .yearly)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
    }

    private func frequencyChip(_ title: String, _ frequency: CardSubscription.Frequency) -> some View {
        let isOn = selectedFrequency == frequency
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedFrequency = frequency }
        } label: {
            Text(title)
                .font(.app(14, weight: .medium))
                .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(isOn ? Color.appText : Color.appFill, in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Pause/resume and delete, only when editing.
    private var manageRow: some View {
        HStack(spacing: 8) {
            Button { togglePause() } label: {
                Label(existing?.isActive == false ? "Aktifkan" : "Jeda",
                      systemImage: existing?.isActive == false ? "play.fill" : "pause.fill")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.appFill, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            Button { showDeleteConfirm = true } label: {
                Label("Hapus", systemImage: "trash")
                    .font(.app(14, weight: .medium))
                    .foregroundStyle(Color.appError)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .overlay(Capsule().stroke(Color.appError.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(PressScaleStyle())
            Spacer(minLength: 0)
        }
        .disabled(isSaving)
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    // MARK: Logic

    private func press(_ key: String) {
        guard let next = NumberPad.apply(key, to: amount) else { return }
        withAnimation(.easeOut(duration: 0.14)) { amount = next }
        bump = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            bump = false
        }
    }

    private func prefill() {
        guard let existing else { return }
        nameText = existing.name
        amount = Int(existing.amount)
        selectedFrequency = existing.frequency
        selectedCategory = expenseCategories.first { $0.id == existing.categoryId }
        if let date = existing.nextBillingDateAsDate {
            billingDay = Calendar.current.component(.day, from: date)
        }
    }

    /// Next date on `billingDay` from today (today included), clamped to short months.
    /// When editing and the day wasn't changed, the stored date stays (yearly ones keep their month).
    private var nextBillingDate: Date {
        if let date = existing?.nextBillingDateAsDate, Calendar.current.component(.day, from: date) == billingDay {
            return date
        }
        return Self.nextOccurrence(ofDay: billingDay, from: Date())
    }

    static func nextOccurrence(ofDay day: Int, from now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = calendar.date(byAdding: .month, value: offset, to: today),
                  let range = calendar.range(of: .day, in: .month, for: month) else { continue }
            var parts = calendar.dateComponents([.year, .month], from: month)
            parts.day = min(day, range.count)
            if let date = calendar.date(from: parts), date >= today { return date }
        }
        return today
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// The chosen category, or "Lainnya" when none was picked.
    private var categoryId: String? {
        (selectedCategory ?? expenseCategories.first { $0.name.localizedCaseInsensitiveCompare("Lainnya") == .orderedSame })?.id
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let name = nameText.trimmingCharacters(in: .whitespaces)
        let value = Double(amount)
        let nextDate = dateString(nextBillingDate)
        Task {
            do {
                await NotificationManager.shared.requestPermissionIfNeeded()
                let saved: CardSubscription
                if let existing {
                    saved = try await SupabaseRepository.shared.updateSubscription(
                        id: existing.id, name: name, amount: value, frequency: selectedFrequency,
                        nextBillingDate: nextDate, isActive: existing.isActive, categoryId: categoryId,
                        note: existing.note, previousAmount: existing.amount
                    )
                } else {
                    saved = try await SupabaseRepository.shared.createSubscription(
                        accountId: account.id, name: name, amount: value, frequency: selectedFrequency,
                        nextBillingDate: nextDate, categoryId: categoryId, note: nil
                    )
                }
                await NotificationManager.shared.schedule(for: saved)
                finish()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = "Gagal menyimpan. Coba lagi."
            }
        }
    }

    private func togglePause() {
        guard let existing else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved = try await SupabaseRepository.shared.updateSubscription(
                    id: existing.id, name: existing.name, amount: existing.amount, frequency: existing.frequency,
                    nextBillingDate: existing.nextBillingDate, isActive: !existing.isActive,
                    categoryId: existing.categoryId, note: existing.note
                )
                if saved.isActive {
                    await NotificationManager.shared.schedule(for: saved)
                } else {
                    await NotificationManager.shared.cancel(for: existing)
                }
                finish()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = "Gagal menyimpan. Coba lagi."
            }
        }
    }

    private func delete() {
        guard let existing else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await SupabaseRepository.shared.deleteSubscription(id: existing.id)
                await NotificationManager.shared.cancel(for: existing)
                finish()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                errorMessage = "Gagal menghapus. Coba lagi."
            }
        }
    }

    private func finish() {
        isSaving = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSave()
        NotificationCenter.default.post(name: .dataDidChange, object: nil)
        dismiss()
    }
}
