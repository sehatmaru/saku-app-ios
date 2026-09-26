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
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        amountSection
                        formCard
                    }
                    .padding(Spacing.lg)
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
            .background(Color.appGroupedBackground)
            .navigationTitle(existing != nil ? "Edit Tagihan" : "Tambah Tagihan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        Button("Simpan") { save() }
                            .font(.app(15, weight: .bold))
                            .foregroundColor(canSave ? .appPrimary : .appTextSecondary.opacity(0.4))
                            .disabled(!canSave)
                    }
                }
            }
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
    }

    // MARK: Amount

    private var amountSection: some View {
        HStack(spacing: 4) {
            Text("Rp")
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Spacer()
            if !amountDigits.isEmpty {
                Button {
                    amountDigits = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(20))
                        .foregroundColor(.appTextSecondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { showKeyboard = true }
    }

    // MARK: Form Card

    private var formCard: some View {
        VStack(spacing: 0) {
            inputRow(icon: "pencil", iconColor: .appTextSecondary, label: "Nama Tagihan") {
                TextField("Contoh: Netflix", text: $nameText)
                    .font(.app(15)).foregroundColor(.appText)
            } accessory: {
                if !nameText.isEmpty { clearBtn { nameText = "" } }
            }

            rowDivider

            tappableRow(icon: selectedCategory?.icon ?? "tag.fill", iconColor: .appExpense, label: "Kategori", value: selectedCategory?.name ?? "Pilih", isSelected: selectedCategory != nil)
                .onTapGesture { showCategoryPicker = true }

            rowDivider

            frequencyRow

            rowDivider

            tappableRow(icon: "calendar", iconColor: .appPrimary, label: "Tagihan Berikutnya", value: formattedDate(selectedDate), isSelected: true)
                .onTapGesture { showDatePicker = true }

            rowDivider

            inputRow(icon: "doc.text", iconColor: .appTextSecondary, label: "Catatan") {
                TextField("Opsional", text: $noteText)
                    .font(.app(15)).foregroundColor(.appText)
            } accessory: {
                if !noteText.isEmpty { clearBtn { noteText = "" } }
            }
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var frequencyRow: some View {
        HStack(spacing: Spacing.md) {
            iconCircle("repeat", .appPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Frekuensi").font(.app(10)).foregroundColor(.appTextSecondary)
                Picker("Frekuensi", selection: $selectedFrequency) {
                    Text("Bulanan").tag(CardSubscription.Frequency.monthly)
                    Text("Tahunan").tag(CardSubscription.Frequency.yearly)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .tint(.appPrimary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    // MARK: Rows

    private func inputRow<Content: View, Accessory: View>(
        icon: String, iconColor: Color, label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: Spacing.md) {
            iconCircle(icon, iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.app(10)).foregroundColor(.appTextSecondary)
                content()
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
    }

    private func tappableRow(icon: String, iconColor: Color, label: String, value: String, isSelected: Bool = false) -> some View {
        HStack(spacing: Spacing.md) {
            iconCircle(icon, isSelected ? iconColor : .appTextSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.app(10)).foregroundColor(.appTextSecondary)
                Text(value).font(.app(15)).foregroundColor(isSelected ? .appText : .appTextSecondary.opacity(0.6))
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.app(10)).foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func iconCircle(_ icon: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
            Image(systemName: icon).font(.app(14, weight: .semibold)).foregroundColor(color)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func clearBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.app(16))
                .foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Pickers

    private var categoryPickerContent: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                    ForEach(expenseCategories) { cat in
                        chipBtn(icon: cat.icon ?? "tag", label: cat.name, color: .appExpense, isSelected: selectedCategory?.id == cat.id) {
                            selectedCategory = cat; showCategoryPicker = false
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Kategori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { showCategoryPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    private func chipBtn(icon: String, label: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon).font(.app(15)).foregroundColor(isSelected ? color : color.opacity(0.7))
                Text(label).font(.app(14)).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
                Spacer(minLength: 0)
                if isSelected { Image(systemName: "checkmark").font(.app(11, weight: .bold)).foregroundColor(color) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(isSelected ? color.opacity(0.1) : Color.appCardBackground)
            .foregroundColor(isSelected ? color : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var datePickerContent: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.appPrimary)
                    .labelsHidden()
                    .onChange(of: selectedDate) { _, _ in showDatePicker = false }
                Spacer()
            }
            .padding(Spacing.lg)
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Tanggal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Batal") { showDatePicker = false } }
            }
        }
        .presentationDetents([.medium])
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
