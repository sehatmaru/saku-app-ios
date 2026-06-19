import SwiftUI

struct BudgetListView: View {
    @StateObject private var viewModel = BudgetListViewModel()

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
        }
    }

    private var summaryCard: some View {
        HStack(spacing: Spacing.xl) {
            summaryItem(title: "Total Budget", amount: viewModel.totalBudget)
            Divider().frame(height: 40)
            summaryItem(title: "Terpakai", amount: viewModel.totalSpent)
            Divider().frame(height: 40)
            summaryItem(title: "Sisa", amount: viewModel.totalBudget - viewModel.totalSpent, color: (viewModel.totalBudget - viewModel.totalSpent) >= 0 ? .appIncome : .appExpense)
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func summaryItem(title: String, amount: Double, color: Color = .appText) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.appTextSecondary)
            Text(amount.formattedAsCurrency())
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "chart.pie")
                .font(.system(size: 40))
                .foregroundColor(.appTextSecondary)
            Text("Belum ada budget")
                .font(.subheadline)
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
                    .font(.body)
                    .foregroundColor(.appPrimary)
                Text(category?.name ?? "Kategori")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(budget.progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(progressColor)
            }

            ProgressView(value: budget.progress)
                .tint(progressColor)

            HStack {
                Text("\(budget.spent.formattedAsCurrency()) / \(budget.amount.formattedAsCurrency())")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
                Spacer()
                if budget.remaining > 0 {
                    Text("Sisa \(budget.remaining.formattedAsCurrency())")
                        .font(.caption2)
                        .foregroundColor(.appTextSecondary)
                } else {
                    Text("Kelebihan \(abs(budget.remaining).formattedAsCurrency())")
                        .font(.caption2)
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
