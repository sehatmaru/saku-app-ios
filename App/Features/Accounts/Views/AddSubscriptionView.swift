import SwiftUI

struct AddSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [Category]
    let account: Account
    let existing: CardSubscription?
    let onSave: () -> Void

    @State private var nameText = ""
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedCategory: Category?
    @State private var selectedFrequency: CardSubscription.Frequency = .monthly
    @State private var selectedDate = Date()
    @State private var noteText = ""
    @State private var showCategoryPicker = false
    @State private var showDatePicker = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    init(categories: [Category], account: Account, existing: CardSubscription? = nil, onSave: @escaping () -> Void) {
        self.categories = categories
        self.account = account
        self.existing = existing
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    amountSection
                    formRows
                        .padding(.top, 12)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .gesture(showKeyboard ? TapGesture().onEnded { showKeyboard = false } : nil)

            if showKeyboard {
                AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                    showKeyboard = false
                }
                .padding(.top, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showKeyboard)
        .background(Color.appBackground)
        .presentationBackground(Color.appBackground)
        .alert("Perhatian", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(validationMessage) }
        .onAppear {
            selectedCategory = existing.flatMap { e in expenseCategories.first { $0.id == e.categoryId } }
            if let existing {
                nameText = existing.name
                amountDigits = String(Int(existing.amount))
                selectedFrequency = existing.frequency
                selectedDate = existing.nextBillingDateAsDate ?? Date()
                noteText = existing.note ?? ""
                if !amountDigits.isEmpty { showKeyboard = false }
            } else {
                showKeyboard = true
            }
        }
        .sheet(isPresented: $showCategoryPicker) { categoryPickerContent }
        .sheet(isPresented: $showDatePicker) { datePickerContent }
    }

    private var topBar: some View {
        HStack {
            Button("Batal") { dismiss() }
                .font(.app(17))
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            if isSaving {
                ProgressView()
                    .tint(.appPrimary)
            } else {
                Button("Simpan") { save() }
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(canSave ? Color.appPrimary : Color.appTextTertiary)
                    .disabled(!canSave)
            }
        }
        .overlay {
            Text(existing != nil ? "Edit tagihan" : "Tambah tagihan")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // MARK: Amount

    private var amountSection: some View {
        HStack(alignment: .center) {
            HeroAmount(value: Double(amountDigits) ?? 0, size: .medium)
                .opacity(amountDigits.isEmpty ? 0.55 : 1)
            Spacer()
            if !amountDigits.isEmpty {
                Button {
                    amountDigits = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hapus nominal")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { showKeyboard = true }
    }

    // MARK: Rows

    private var formRows: some View {
        VStack(spacing: 0) {
            fieldRow("Nama", placeholder: "Contoh: Netflix", text: $nameText)

            Button { showCategoryPicker = true } label: {
                DetailRow(label: "Kategori", value: selectedCategory?.name ?? "Pilih",
                          icon: selectedCategory?.icon ?? "tag", showsChevron: true)
            }
            .buttonStyle(RowPressStyle())

            frequencyRow

            Button { showDatePicker = true } label: {
                DetailRow(label: "Tagihan", value: formattedDate(selectedDate), icon: "calendar", showsChevron: true)
            }
            .buttonStyle(RowPressStyle())

            fieldRow("Catatan", placeholder: "Opsional", text: $noteText)
        }
    }

    private func fieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.app(16, weight: .medium))
                .foregroundStyle(Color.appText)
                .submitLabel(.done)
            if !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hapus \(label.lowercased())")
            }
        }
        .frame(height: 52)
        .padding(.leading, 24)
        .padding(.trailing, 20)
        .rowSeparator()
    }

    private var frequencyRow: some View {
        HStack(spacing: 12) {
            Text("Frekuensi")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 76, alignment: .leading)
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

    // MARK: Pickers

    private var categoryPickerContent: some View {
        PickerSheet(title: "Pilih kategori", onDone: { showCategoryPicker = false }) {
            CategoryPickerGrid(categories: expenseCategories, selectedId: selectedCategory?.id, color: .appError) { cat in
                selectedCategory = cat; showCategoryPicker = false
            }
        }
    }

    private var datePickerContent: some View {
        PickerSheet(title: "Tagihan berikutnya", onDone: { showDatePicker = false }) {
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.appPrimary)
                .labelsHidden()
                .onChange(of: selectedDate) { _, _ in showDatePicker = false }
                .padding(.horizontal, 16)
        }
    }

    // MARK: Helpers

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private var canSave: Bool {
        guard !amountDigits.isEmpty, let amount = Double(amountDigits), amount > 0 else { return false }
        guard !nameText.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return selectedCategory != nil
    }

    private func save() {
        guard let amount = Double(amountDigits), amount > 0 else {
            validationMessage = "Nominal tidak valid."; showValidationAlert = true; return
        }
        guard let category = selectedCategory else {
            validationMessage = "Pilih kategori tagihan."; showValidationAlert = true; return
        }
        isSaving = true
        Task {
            do {
                await NotificationManager.shared.requestPermissionIfNeeded()
                let nextDate = dateString(selectedDate)
                if let existing {
                    _ = try await SupabaseRepository.shared.updateSubscription(
                        id: existing.id, name: nameText.trimmingCharacters(in: .whitespaces),
                        amount: amount, frequency: selectedFrequency, nextBillingDate: nextDate,
                        isActive: existing.isActive, categoryId: category.id, note: noteText.isEmpty ? nil : noteText
                    )
                } else {
                    _ = try await SupabaseRepository.shared.createSubscription(
                        accountId: account.id, name: nameText.trimmingCharacters(in: .whitespaces),
                        amount: amount, frequency: selectedFrequency, nextBillingDate: nextDate,
                        categoryId: category.id, note: noteText.isEmpty ? nil : noteText
                    )
                }
                isSaving = false
                onSave()
                NotificationCenter.default.post(name: .dataDidChange, object: nil)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                isSaving = false
                validationMessage = "Gagal menyimpan: \(error.localizedDescription)"; showValidationAlert = true
            }
        }
    }
}
