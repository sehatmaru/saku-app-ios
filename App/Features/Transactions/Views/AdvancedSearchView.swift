import SwiftUI

struct AdvancedSearchView: View {
    @Binding var filter: TransactionFilter
    @Environment(\.dismiss) private var dismiss
    let categories: [Category]

    @State private var draft: TransactionFilter
    @State private var showAllExpense = false

    init(filter: Binding<TransactionFilter>, categories: [Category]) {
        self._filter = filter
        self.categories = categories
        self._draft = State(initialValue: filter.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    typeSection
                    Divider()
                    expenseCategorySection
                    Divider()
                    incomeCategorySection
                    Divider()
                    dateRangeSection
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        filter.reset()
                        dismiss()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.jakarta(11))
                            Text("Reset")
                                .font(.jakarta(13))
                        }
                    }
                    .foregroundColor(.appExpense)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    // MARK: Transaction Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Kategori Transaksi", icon: "arrow.left.arrow.right")

            HStack(spacing: 0) {
                typeSegment(title: "Pemasukan", isSelected: draft.transactionTypes.contains(.income)) {
                    toggleDraftType(.income)
                }
                typeSegmentDivider
                typeSegment(title: "Pengeluaran", isSelected: draft.transactionTypes.contains(.expense)) {
                    toggleDraftType(.expense)
                }
                typeSegmentDivider
                typeSegment(title: "Transfer", isSelected: draft.transactionTypes.contains(.transfer)) {
                    toggleDraftType(.transfer)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func typeSegment(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.jakarta(13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.appPrimary : Color.clear)
                .foregroundColor(isSelected ? .white : .appText)
        }
        .buttonStyle(.plain)
    }

    private var typeSegmentDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
    }

    private func toggleDraftType(_ type: Transaction.TransactionType) {
        if draft.transactionTypes.contains(type) {
            draft.transactionTypes.remove(type)
        } else {
            draft.transactionTypes.insert(type)
        }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.type == .expense }
    }

    // MARK: Expense Categories

    private var expenseCategorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Kategori Pengeluaran", icon: "arrow.up")

            let items = showAllExpense
                ? expenseCategories
                : Array(expenseCategories.prefix(4))

            LazyVGrid(
                columns: Array(repeating: .init(.flexible(), spacing: Spacing.sm), count: 2),
                spacing: Spacing.sm
            ) {
                ForEach(items) { category in
                    categoryChip(
                        category: category,
                        isSelected: draft.expenseCategoryIds.contains(category.id)
                    ) {
                        if draft.expenseCategoryIds.contains(category.id) {
                            draft.expenseCategoryIds.remove(category.id)
                        } else {
                            draft.expenseCategoryIds.insert(category.id)
                        }
                    }
                }
            }

            if expenseCategories.count > 4 {
                Button {
                    withAnimation { showAllExpense.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(showAllExpense ? "Ringkas" : "Lihat Semua (\(expenseCategories.count))")
                            .font(.jakarta(13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.jakarta(10))
                            .rotationEffect(.degrees(showAllExpense ? 180 : 0))
                    }
                    .foregroundColor(.appPrimary)
                }
            }
        }
    }

    // MARK: Income Categories

    private var incomeCategorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Kategori Pemasukan", icon: "arrow.down")

            let incomeCategories = categories.filter { $0.type == .income }
            if incomeCategories.isEmpty {
                Text("Tidak ada kategori pemasukan")
                    .font(.jakarta(13))
                    .foregroundColor(.appTextSecondary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: .init(.flexible(), spacing: Spacing.sm), count: 2),
                    spacing: Spacing.sm
                ) {
                    ForEach(incomeCategories) { category in
                        categoryChip(
                            category: category,
                            isSelected: draft.incomeCategoryIds.contains(category.id)
                        ) {
                            if draft.incomeCategoryIds.contains(category.id) {
                                draft.incomeCategoryIds.remove(category.id)
                            } else {
                                draft.incomeCategoryIds.insert(category.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Date Range

    @State private var showStartPicker = false
    @State private var showEndPicker = false
    @State private var selectedDatePreset: DatePreset?

    private enum DatePreset: String, CaseIterable {
        case today = "Hari Ini"
        case sevenDays = "7 Hari"
        case thirtyDays = "30 Hari"
        case thisMonth = "Bulan Ini"
    }

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Range Tanggal", icon: "calendar")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    datePresetChip(preset: .today, isSelected: selectedDatePreset == .today) {
                        selectedDatePreset = .today
                        let today = Date()
                        draft.dateFrom = today
                        draft.dateTo = today
                    }
                    datePresetChip(preset: .sevenDays, isSelected: selectedDatePreset == .sevenDays) {
                        selectedDatePreset = .sevenDays
                        draft.dateTo = Date()
                        draft.dateFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date())
                    }
                    datePresetChip(preset: .thirtyDays, isSelected: selectedDatePreset == .thirtyDays) {
                        selectedDatePreset = .thirtyDays
                        draft.dateTo = Date()
                        draft.dateFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date())
                    }
                    datePresetChip(preset: .thisMonth, isSelected: selectedDatePreset == .thisMonth) {
                        selectedDatePreset = .thisMonth
                        let now = Date()
                        draft.dateTo = now
                        draft.dateFrom = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now))
                    }
                }
            }

            HStack(spacing: 0) {
                Button {
                    selectedDatePreset = nil
                    showStartPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.jakarta(12))
                            .foregroundColor(.appPrimary)
                        Group {
                            if let date = draft.dateFrom {
                                Text(date.formatted(date: .numeric, time: .omitted))
                            } else {
                                Text("Pilih tanggal")
                            }
                        }
                        .font(.jakarta(14, weight: .medium))
                        if draft.dateFrom != nil {
                            Button {
                                selectedDatePreset = nil
                                draft.dateFrom = nil
                                draft.dateTo = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.jakarta(12))
                                    .foregroundColor(.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundColor(draft.dateFrom != nil ? .appText : .appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 24)

                Button {
                    selectedDatePreset = nil
                    guard draft.dateFrom != nil else { return }
                    showEndPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.jakarta(12))
                            .foregroundColor(.appPrimary)
                        Group {
                            if let date = draft.dateTo {
                                Text(date.formatted(date: .numeric, time: .omitted))
                            } else {
                                Text("Pilih tanggal")
                            }
                        }
                        .font(.jakarta(14, weight: .medium))
                        if draft.dateTo != nil {
                            Button {
                                selectedDatePreset = nil
                                draft.dateTo = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.jakarta(12))
                                    .foregroundColor(.appTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundColor(draft.dateTo != nil ? .appText : .appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .disabled(draft.dateFrom == nil)
                .opacity(draft.dateFrom == nil ? 0.4 : 1)
            }
            .padding(.horizontal, Spacing.md)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showStartPicker) {
            datePickerSheet(
                title: "Dari Tanggal",
                date: Binding(
                    get: { draft.dateFrom ?? Date() },
                    set: {
                        draft.dateFrom = $0
                        showStartPicker = false
                    }
                )
            )
        }
        .sheet(isPresented: $showEndPicker) {
            datePickerSheet(
                title: "Sampai Tanggal",
                date: Binding(
                    get: { draft.dateTo ?? draft.dateFrom ?? Date() },
                    set: {
                        draft.dateTo = $0
                        showEndPicker = false
                    }
                ),
                minimumDate: draft.dateFrom
            )
        }
    }

    private func datePresetChip(preset: DatePreset, isSelected: Bool, action: @escaping () -> Void) -> some View {
        FilterChip(title: preset.rawValue, isSelected: isSelected, action: action)
    }

    private func datePickerSheet(title: String, date: Binding<Date>, minimumDate: Date? = nil) -> some View {
        NavigationStack {
            DatePicker(title, selection: date, in: minimumDate.map { $0... } ?? Date.distantPast..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.appPrimary)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Selesai") {
                            if title == "Dari Tanggal" {
                                showStartPicker = false
                            } else {
                                showEndPicker = false
                            }
                        }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: Shared Components

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.jakarta(13))
                .foregroundColor(.appPrimary)
            Text(title)
                .font(.jakarta(15, weight: .semibold))
        }
    }

    private func categoryChip(category: Category, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: category.icon ?? "tag")
                    .font(.jakarta(14))

                Text(category.name)
                    .font(.jakarta(13))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.jakarta(10, weight: .bold))
                        .foregroundColor(Color.appPrimary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .background(isSelected ? Color.appPrimary.opacity(0.12) : Color(.systemGray6))
            .foregroundColor(isSelected ? Color.appPrimary : .appText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        Button("Terapkan Filter") {
            filter = draft
            dismiss()
        }
        .font(.jakarta(15, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.appPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, Spacing.sm)
        .background(Color.appCardBackground)
    }
}

#Preview {
    AdvancedSearchView(
        filter: .constant(TransactionFilter()),
        categories: []
    )
}
