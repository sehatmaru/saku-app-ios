import SwiftUI

struct AnalyticsView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                healthSection
                cashflowSection
                spendingSection
            }
            .padding()
        }
        .background(Color.appGroupedBackground)
        .navigationTitle("Analitik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var healthSection: some View {
        VStack(spacing: Spacing.lg) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Skor Kesehatan Finansial")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(.appText)
                Spacer()
            }

            HStack(spacing: Spacing.xxl) {
                ZStack {
                    Circle()
                        .stroke(Color.appGroupedBackground, lineWidth: 10)
                        .frame(width: 120, height: 120)

                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.healthScore) / 100)
                        .stroke(healthScoreColor(viewModel.healthScore), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: -2) {
                        Text("\(viewModel.healthScore)")
                            .font(.jakarta(38, weight: .bold))
                            .foregroundColor(healthScoreColor(viewModel.healthScore))
                        Text("/100")
                            .font(.jakarta(11))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(viewModel.healthScoreLabel)
                        .font(.jakarta(22, weight: .bold))
                        .foregroundColor(healthScoreColor(viewModel.healthScore))

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        detailRow(label: "Arus Kas", score: viewModel.cashflowScore, maxScore: 40)
                        detailRow(label: "Budget", score: viewModel.budgetScore, maxScore: 35)
                        detailRow(label: "Diversifikasi", score: viewModel.diversityScore, maxScore: 25)
                    }
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func detailRow(label: String, score: Int, maxScore: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(label)
                .font(.jakarta(13))
                .foregroundColor(.appTextSecondary)
            ProgressView(value: Double(score) / Double(maxScore))
                .tint(healthScoreColor(score * 100 / max(maxScore, 1)))
                .frame(width: 60)
            Text("\(score)/\(maxScore)")
                .font(.jakarta(12, weight: .semibold))
                .foregroundColor(.appText)
        }
    }

    private func healthScoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .appIncome
        case 60..<80: return Color(red: 0.85, green: 0.65, blue: 0.13)
        case 40..<60: return .appWarning
        default: return .appError
        }
    }

    private var cashflowSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Cashflow 5 Bulan Terakhir")
                    .font(.jakarta(15, weight: .semibold))
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
                            .font(.jakarta(8))
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
                            .font(.jakarta(8))
                            .foregroundColor(.appExpense)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Text(item.0)
                            .font(.jakarta(10))
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
                        .font(.jakarta(11))
                        .foregroundColor(.appTextSecondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.appExpense).frame(width: 10, height: 10)
                    Text("Pengeluaran")
                        .font(.jakarta(11))
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
                    .font(.jakarta(12))
                    .foregroundColor(.appPrimary)
                Text("Pengeluaran Bulan Ini")
                    .font(.jakarta(15, weight: .semibold))
                    .foregroundColor(.appText)
                Spacer()
                Text("Total: \(viewModel.totalExpense.formattedAsCurrency())")
                    .font(.jakarta(11))
                    .foregroundColor(.appTextSecondary)
            }

            let total = viewModel.categorySpending.map(\.amount).reduce(0, +)

            ForEach(viewModel.categorySpending, id: \.0.id) { cat, amount in
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: cat.icon ?? "tag")
                            .font(.jakarta(12))
                            .foregroundColor(.appPrimary)
                            .frame(width: 24)

                        Text(cat.name)
                            .font(.jakarta(14))
                            .foregroundColor(.appText)
                        Spacer()
                        Text(amount.formattedAsCurrency())
                            .font(.jakarta(14, weight: .semibold))
                            .foregroundColor(.appText)
                        Text("(\(Int(total > 0 ? amount / total * 100 : 0))%)")
                            .font(.jakarta(12))
                            .foregroundColor(.appTextSecondary)
                    }

                    ProgressView(value: total > 0 ? amount / total : 0)
                        .tint(.appExpense)
                }
            }

            if viewModel.categorySpending.isEmpty {
                Text("Belum ada pengeluaran bulan ini")
                    .font(.jakarta(14))
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
