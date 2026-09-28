import SwiftUI

struct AnalyticsView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                cashflowSection
                spendingSection
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Analitik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cashflowSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.app(12))
                    .foregroundColor(.appPrimary)
                Text("Cashflow 5 Bulan Terakhir")
                    .font(.app(15, weight: .semibold))
                    .foregroundColor(.appText)
            }

            let maxAmount = max(
                viewModel.monthlyCashflow.map(\.income).max() ?? 1,
                viewModel.monthlyCashflow.map(\.expense).max() ?? 1
            )

            HStack(alignment: .bottom, spacing: Spacing.md) {
                ForEach(viewModel.monthlyCashflow.indices, id: \.self) { idx in
                    let item = viewModel.monthlyCashflow[idx]
                    VStack(spacing: 4) {
                        Text(item.income.formattedAsCurrency())
                            .font(.app(8))
                            .foregroundColor(.appIncome)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Rectangle()
                            .fill(Color.appIncome)
                            .frame(width: 20, height: max(4, item.income / maxAmount * 120))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Rectangle()
                            .fill(Color.appExpense)
                            .frame(width: 20, height: max(4, item.expense / maxAmount * 120))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(item.expense.formattedAsCurrency())
                            .font(.app(8))
                            .foregroundColor(.appExpense)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(item.0)
                            .font(.app(10))
                            .foregroundColor(.appTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 200)
            .padding(.top, Spacing.sm)

            HStack(spacing: Spacing.md) {
                HStack(spacing: 4) {
                    Circle().fill(Color.appIncome).frame(width: 10, height: 10)
                    Text("Pemasukan")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.appExpense).frame(width: 10, height: 10)
                    Text("Pengeluaran")
                        .font(.app(11))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var spendingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.app(12))
                    .foregroundColor(.appPrimary)
                Text("Pengeluaran Bulan Ini")
                    .font(.app(15, weight: .semibold))
                    .foregroundColor(.appText)
                Spacer()
                Text("Total: \(viewModel.totalExpense.formattedAsCurrency())")
                    .font(.app(11))
                    .foregroundColor(.appTextSecondary)
            }

            let total = viewModel.categorySpending.map(\.amount).reduce(0, +)

            ForEach(viewModel.categorySpending, id: \.0.id) { cat, amount in
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: cat.icon ?? "tag")
                            .font(.app(12))
                            .foregroundColor(.appPrimary)
                            .frame(width: 24)

                        Text(cat.name)
                            .font(.app(14))
                            .foregroundColor(.appText)
                        Spacer()
                        Text(amount.formattedAsCurrency())
                            .font(.app(14, weight: .semibold))
                            .foregroundColor(.appText)
                        Text("(\(Int(total > 0 ? amount / total * 100 : 0))%)")
                            .font(.app(12))
                            .foregroundColor(.appTextSecondary)
                    }

                    ProgressView(value: total > 0 ? amount / total : 0)
                        .tint(.appExpense)
                }
            }

            if viewModel.categorySpending.isEmpty {
                Text("Belum ada pengeluaran bulan ini")
                    .font(.app(14))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
