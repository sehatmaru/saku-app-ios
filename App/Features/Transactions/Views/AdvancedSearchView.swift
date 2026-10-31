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
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    typeSection
                    SectionDivider()
                    expenseCategorySection
                    SectionDivider()
                    incomeCategorySection
                    SectionDivider()
                    dateRangeSection
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            Text("Filter")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
            HStack {
                Spacer()
                Button("Reset") {
                    filter.reset()
                    dismiss()
                }
                .font(.app(16))
                .foregroundStyle(Color.appError)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    // MARK: Transaction Type

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Jenis transaksi"))
            HStack(spacing: 8) {
                typeChip(L("Pemasukan"), .income)
                typeChip(L("Pengeluaran"), .expense)
                typeChip(L("Transfer"), .transfer)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    private func typeChip(_ title: String, _ type: Transaction.TransactionType) -> some View {
        FilterChip(title: title, isSelected: draft.transactionTypes.contains(type)) {
            toggleDraftType(type)
        }
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
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                title: L("Kategori pengeluaran"),
                trailing: expenseCategories.count > 8 ? (showAllExpense ? L("Ringkas") : L("Lihat semua")) : nil,
                trailingColor: .appPrimary,
                action: { withAnimation(.snappy) { showAllExpense.toggle() } }
            )

            let items = showAllExpense ? expenseCategories : Array(expenseCategories.prefix(8))
            if items.isEmpty {
                emptyText(L("Tidak ada kategori pengeluaran"))
            } else {
                ChipFlow {
                    ForEach(items) { category in
                        categoryChip(category: category, isSelected: draft.expenseCategoryIds.contains(category.id)) {
                            if draft.expenseCategoryIds.contains(category.id) {
                                draft.expenseCategoryIds.remove(category.id)
                            } else {
                                draft.expenseCategoryIds.insert(category.id)
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
        .sectionPadding()
    }

    // MARK: Income Categories

    private var incomeCategorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Kategori pemasukan"))

            let incomeCategories = categories.filter { $0.type == .income }
            if incomeCategories.isEmpty {
                emptyText(L("Tidak ada kategori pemasukan"))
            } else {
                ChipFlow {
                    ForEach(incomeCategories) { category in
                        categoryChip(category: category, isSelected: draft.incomeCategoryIds.contains(category.id)) {
                            if draft.incomeCategoryIds.contains(category.id) {
                                draft.incomeCategoryIds.remove(category.id)
                            } else {
                                draft.incomeCategoryIds.insert(category.id)
                            }
                        }
                    }
                }
                .padding(.top, 14)
            }
        }
        .sectionPadding()
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
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Rentang tanggal"))
                .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                        draft.dateTo = Date()
                        draft.dateFrom = PaydayCycle.current.period(containing: Date()).start
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 14)
            .padding(.bottom, 8)

            dateRow(label: L("Dari"), date: draft.dateFrom, onTap: {
                selectedDatePreset = nil
                showStartPicker = true
            }, onClear: {
                selectedDatePreset = nil
                draft.dateFrom = nil
                draft.dateTo = nil
            })

            dateRow(label: L("Sampai"), date: draft.dateTo, onTap: {
                selectedDatePreset = nil
                guard draft.dateFrom != nil else { return }
                showEndPicker = true
            }, onClear: {
                selectedDatePreset = nil
                draft.dateTo = nil
            })
            .disabled(draft.dateFrom == nil)
            .opacity(draft.dateFrom == nil ? 0.4 : 1)
        }
        .padding(.top, 28)
        .sheet(isPresented: $showStartPicker) {
            datePickerSheet(
                title: L("Dari Tanggal"),
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
                title: L("Sampai Tanggal"),
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

    /// Label left, date right, like the form rows in AddTransactionView; a clear button once set.
    private func dateRow(label: String, date: Date?, onTap: @escaping () -> Void, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Text(label)
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 76, alignment: .leading)
                    Text(date?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.locale)) ?? L("Pilih tanggal"))
                        .font(.app(16, weight: date == nil ? .regular : .medium))
                        .foregroundStyle(date == nil ? Color.appTextTertiary : Color.appText)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if date == nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.appTextTertiary)
                    }
                }
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            if date != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Hapus tanggal %@", label.lowercased()))
            }
        }
        .padding(.horizontal, 24)
        .rowSeparator()
    }

    private func datePresetChip(preset: DatePreset, isSelected: Bool, action: @escaping () -> Void) -> some View {
        FilterChip(title: L(preset.rawValue), isSelected: isSelected, action: action)
    }

    private func datePickerSheet(title: String, date: Binding<Date>, minimumDate: Date? = nil) -> some View {
        NavigationStack {
            DatePicker(title, selection: date, in: minimumDate.map { $0... } ?? Date.distantPast..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(.appPrimary)
                .padding(.horizontal, 16)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Selesai") {
                            if title == L("Dari Tanggal") {
                                showStartPicker = false
                            } else {
                                showEndPicker = false
                            }
                        }
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Color.appPrimary)
                    }
                }
        }
        .presentationDetents([.medium])
    }

    // MARK: Shared Components

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.app(15))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.top, 12)
    }

    /// FilterChip look with the category icon in front.
    private func categoryChip(category: Category, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon ?? "tag")
                    .font(.system(size: 13))
                Text(category.name)
                    .font(.app(14, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(isSelected ? Color.appBackground : Color.appText)
            .background(isSelected ? Color.appText : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.appBorder))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var bottomBar: some View {
        SmartSheetFooter(primary: L("Terapkan Filter"), secondary: L("Batal"), onPrimary: {
            filter = draft
            dismiss()
        }) { dismiss() }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, Self.footerBottomPadding)
        .background(Color.appBackground)
    }
}

private extension View {
    func sectionPadding() -> some View {
        padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 28)
    }
}

/// Wraps chips onto as many lines as needed.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in rows.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (origins, maxX, y + lineHeight)
    }
}
