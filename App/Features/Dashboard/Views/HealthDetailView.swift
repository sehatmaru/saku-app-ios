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
                Text("Setiap faktor punya poin maksimal, dan skor adalah poin yang kamu dapat dibagi poin yang bisa dinilai. Faktor yang belum bisa dinilai, misalnya karena belum punya kartu kredit, dilewati. Skor diperbarui setiap kamu mencatat transaksi.")
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
                Text(health.label)
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(health.color)
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
        var text = L("Kamu dapat %lld dari 100 poin.", health.score)
        if let weakest = health.weakest {
            text += " " + L("Yang paling mengurangi: %@, kurang %lld poin.", weakest.title, weakest.missing)
        } else {
            text += " " + L("Semua faktor di bawah dalam kondisi baik.")
        }
        let pending = health.factors.filter(\.isPending).map(\.title)
        if !pending.isEmpty {
            text += " " + L("Belum dinilai dan tidak dihitung: %@.", pending.joined(separator: ", "))
        }
        return text
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
                Text(factor.about)
                    .font(.app(13))
                    .foregroundStyle(Color.appTextTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                SegmentBar(value: factor.ratio, color: factor.color, count: 20, height: 6, spacing: 2)
                Text(factor.summary)
                    .font(.app(14, weight: .medium))
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
        case 0.8...: .appPrimary
        case 0.6..<0.8: .appWarning
        default: .appError
        }
    }
}

extension FinancialHealth.Factor {
    var color: Color { FinancialHealth.color(forShare: ratio) }
}
