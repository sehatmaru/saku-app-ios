import SwiftUI

/// Kesehatan finansial in full: the score, every factor behind it, and what to do next.
struct HealthDetailView: View {
    let health: FinancialHealth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if health.isAvailable {
                    hero
                    SectionDivider()
                    factorsSection
                    if !health.recommendations.isEmpty {
                        SectionDivider()
                        recommendationsSection
                    }
                } else {
                    emptyHero
                }
                Text("Dihitung dari pemasukan dan pengeluaran 3 bulan terakhir, saldo dompet, kartu kredit, dan budget bulan ini. Skor diperbarui setiap kamu mencatat transaksi.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .lineSpacing(2)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 100)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Kesehatan finansial")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: Score

    /// Before the first transaction there is no score to explain.
    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("–")
                    .font(.app(64, weight: .light))
                    .tracking(-2.4)
                    .foregroundStyle(Color.appTextTertiary)
                Text("/ 100")
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
            }
            SegmentBar(value: 0, count: 40, height: 22, spacing: 3)
                .padding(.top, 16)
            Text("Skor muncul setelah kamu mencatat pemasukan atau pengeluaran.")
                .font(.app(15))
                .foregroundStyle(Color.appBody)
                .lineSpacing(3)
                .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 28)
    }


    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(health.score)")
                        .font(.app(64, weight: .light))
                        .tracking(-2.4)
                        .foregroundStyle(Color.appText)
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.app(17))
                        .foregroundStyle(Color.appTextSecondary)
                }
                Spacer()
                if let label = health.label {
                    Text(label)
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(health.color)
                } else {
                    Text("Sementara")
                        .font(.app(14, weight: .semibold))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.appFill, in: Capsule())
                }
            }

            SegmentBar(value: Double(health.score) / 100, color: health.color, count: 40, height: 22, spacing: 3)
                .padding(.top, 16)

            Text(verdict)
                .font(.app(15))
                .foregroundStyle(Color.appBody)
                .lineSpacing(3)
                .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private var verdict: String {
        if health.isHealthy { return L("Keuanganmu sehat. Pertahankan kebiasaan ini.") }
        guard let weakest = health.weakest else {
            return health.isProvisional ? L("Skor sementara. Skor lengkap muncul setelah 3 bulan pemakaian.") : ""
        }
        return L("%@ paling menahan skormu. Perbaiki itu dulu untuk menambah hingga %lld poin.", weakest.title, weakest.missing)
    }

    // MARK: Factors

    private var factorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Yang memengaruhi skor"))
            ForEach(health.factors) { factor in
                factorRow(factor)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private func factorRow(_ factor: FinancialHealth.Factor) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: factor.icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24, height: 22)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(factor.title)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                    Spacer()
                    (Text(factor.isPending ? "–" : "\(factor.points)").foregroundStyle(Color.appText)
                     + Text("/\(factor.maxPoints)").foregroundStyle(Color.appTextTertiary))
                        .font(.app(15))
                        .monospacedDigit()
                }
                SegmentBar(value: factor.ratio, color: factor.color, count: 20, height: 6, spacing: 2)
                Text(factor.summary)
                    .font(.app(14))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: L("Rekomendasi"))
            VStack(spacing: 10) {
                ForEach(Array(health.recommendations.enumerated()), id: \.element.id) { index, factor in
                    recommendationCard(factor, number: index + 1)
                }
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }

    private func recommendationCard(_ factor: FinancialHealth.Factor, number: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.app(14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(number == 1 ? health.color : Color.appTextTertiary, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(factor.title)
                        .font(.app(16, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    Spacer()
                    if factor.missing > 0 {
                        Text("+\(factor.missing) poin")
                            .font(.app(13, weight: .medium))
                            .foregroundStyle(Color.appPrimary)
                            .monospacedDigit()
                    }
                }
                Text(factor.tip ?? "")
                    .font(.app(15))
                    .foregroundStyle(Color.appBody)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

extension FinancialHealth {
    /// Green when healthy, amber in the middle, red when it needs work.
    var color: Color { Self.color(forShare: Double(score) / 100) }

    static func color(forShare share: Double) -> Color {
        switch share {
        case 0.6...: .appPrimary
        case 0.4..<0.6: .appWarning
        default: .appError
        }
    }
}

extension FinancialHealth.Factor {
    var color: Color { FinancialHealth.color(forShare: ratio) }
}
