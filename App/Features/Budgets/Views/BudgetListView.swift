import SwiftUI

struct BudgetListView: View {
    @StateObject private var viewModel = BudgetListViewModel()
    @State private var showAddBudget = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    summaryCard

                    if viewModel.budgets.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.budgets) { budget in
                            BudgetCardView(budget: budget)
                        }
                    }
                }
                .padding()
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Budget")
            .onAppear {
                viewModel.loadBudgets()
            }
            .alert("Tambah Budget", isPresented: $showAddBudget) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Fitur akan segera tersedia.")
            }
        }
    }

    private var summaryCard: some View {
        let remaining = viewModel.totalBudget - viewModel.totalSpent
        let ratio = viewModel.totalBudget > 0 ? viewModel.totalSpent / viewModel.totalBudget : 0

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Ringkasan Budget")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)

            Text(viewModel.totalBudget.formattedAsCurrency())
                .font(.jakarta(34, weight: .bold))
                .foregroundColor(.appText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)

            Divider()
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.lg)

            VStack(spacing: Spacing.sm) {
                ProgressView(value: ratio)
                    .tint(ratio >= 1 ? .appError : ratio >= 0.8 ? .appWarning : .appPrimary)

                HStack {
                    HStack(spacing: 4) {
                        Circle().fill(Color.appExpense).frame(width: 8, height: 8)
                        Text("Terpakai \(viewModel.totalSpent.formattedAsCurrency())")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(remaining >= 0 ? Color.appIncome : Color.appError).frame(width: 8, height: 8)
                        Text("Sisa \(remaining.formattedAsCurrency())")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)

            Button {
                showAddBudget = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.jakarta(15, weight: .semibold))
                    Text("Tambah Budget")
                        .font(.jakarta(15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.appCardBackground)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 48))
                .foregroundColor(.appPrimary.opacity(0.08))
                .offset(x: -12, y: -4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "chart.pie")
                .font(.jakarta(40))
                .foregroundColor(.appTextSecondary)
            Text("Belum ada budget")
                .font(.jakarta(15))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxxl)
    }
}

struct BudgetCardView: View {
    let budget: Budget

    private var category: Category? {
        Category.sample.first(where: { $0.id == budget.categoryId })
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: category?.icon ?? "questionmark")
                    .font(.jakarta(17))
                    .foregroundColor(.appPrimary)
                Text(category?.name ?? "Kategori")
                    .font(.jakarta(15, weight: .medium))
                Spacer()
                Text("\(Int(budget.progress * 100))%")
.font(.jakarta(12, weight: .semibold))
                    .foregroundColor(progressColor)
            }

            ProgressView(value: budget.progress)
                .tint(progressColor)

            HStack {
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.jakarta(12))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                if budget.remaining > 0 {
                    Text("Sisa \(budget.remaining.formattedAsCurrency())")
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                } else {
                    Text("Kelebihan \(abs(budget.remaining).formattedAsCurrency())")
                        .font(.jakarta(11))
                        .foregroundColor(.appError)
                }
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var progressColor: Color {
        if budget.progress >= 1.0 { return .appError }
        if budget.progress >= 0.8 { return .appWarning }
        return .appPrimary
    }
}
