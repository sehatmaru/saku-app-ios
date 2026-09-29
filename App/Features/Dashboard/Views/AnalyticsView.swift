import SwiftUI

struct AnalyticsView: View {
    let viewModel: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cashflowSection
                SectionDivider()
                spendingSection
            }
            .padding(.bottom, 100)
        }
        .background(Color.appBackground)
        .navigationTitle("Analitik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: Cashflow

    private var cashflowSection: some View {
        let months = viewModel.monthlyCashflow
        let maxAmount = max(months.map(\.income).max() ?? 0, months.map(\.expense).max() ?? 0, 1)

        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Cashflow 5 bulan terakhir")

            HStack(spacing: 16) {
                legend("Pemasukan", color: .appPrimary)
                legend("Pengeluaran", color: .appText)
            }
            .padding(.top, 8)

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(months.indices, id: \.self) { idx in
                    let item = months[idx]
                    let isCurrent = idx == months.count - 1
                    VStack(spacing: 10) {
                        HStack(alignment: .bottom, spacing: 4) {
                            bar(item.income / maxAmount, color: .appPrimary)
                            bar(item.expense / maxAmount, color: .appText)
                        }
                        .frame(height: chartHeight, alignment: .bottom)
                        Text(item.0)
                            .font(.app(13, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? Color.appText : Color.appTextSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.0): pemasukan \(item.income.formattedAsCurrency()), pengeluaran \(item.expense.formattedAsCurrency())")
                }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private let chartHeight: CGFloat = 160

    private func bar(_ share: Double, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(share > 0 ? color : Color.appDivider)
            .frame(width: 14, height: max(3, share * chartHeight))
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
    }

    // MARK: Spending per category

    private var spendingSection: some View {
        let total = viewModel.categorySpending.map(\.amount).reduce(0, +)

        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Pengeluaran bulan ini", trailing: viewModel.totalExpense.formattedAsCurrency())

            if viewModel.categorySpending.isEmpty {
                EmptyMessage(icon: "chart.bar", title: "Belum ada pengeluaran",
                             message: "Belum ada pengeluaran bulan ini")
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.categorySpending, id: \.0.id) { cat, amount in
                        categoryRow(cat, amount: amount, share: total > 0 ? amount / total : 0)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private func categoryRow(_ cat: Category, amount: Double, share: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: cat.icon ?? "tag")
                .font(.system(size: 18))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cat.name)
                        .font(.app(16))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(amount.formattedAsCurrency())
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(Int(share * 100))%")
                        .font(.app(13))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(minWidth: 34, alignment: .trailing)
                }
                .monospacedDigit()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.appDivider)
                        RoundedRectangle(cornerRadius: 3).fill(Color.appText)
                            .frame(width: geo.size.width * min(max(share, 0), 1))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .rowSeparator()
        .accessibilityElement(children: .combine)
    }
}
