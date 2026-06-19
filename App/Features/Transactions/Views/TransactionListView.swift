import SwiftUI

struct TransactionListView: View {
    @StateObject private var viewModel = TransactionListViewModel()
    @State private var selectedFilter: Transaction.TransactionType?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips

                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(filteredTransactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Transaksi")
            .onAppear {
                viewModel.loadTransactions()
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                FilterChip(title: "Semua", isSelected: selectedFilter == nil) {
                    selectedFilter = nil
                }
                FilterChip(title: "Pemasukan", isSelected: selectedFilter == .income) {
                    selectedFilter = .income
                }
                FilterChip(title: "Pengeluaran", isSelected: selectedFilter == .expense) {
                    selectedFilter = .expense
                }
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.appBackground)
    }

    private var filteredTransactions: [Transaction] {
        guard let filter = selectedFilter else { return viewModel.transactions }
        return viewModel.transactions.filter { $0.type == filter }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "tray")
                .font(.jakarta(40))
                .foregroundColor(.appTextSecondary)
            Text("Belum ada transaksi")
                .font(.jakarta(15))
                .foregroundColor(.appTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.jakarta(15))
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? Color.appPrimary : Color(.systemGray6))
                .foregroundColor(isSelected ? .white : .appText)
                .clipShape(Capsule())
        }
    }
}
