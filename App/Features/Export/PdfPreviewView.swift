import SwiftUI

/// What a free account sees when it taps Laporan PDF (Fitur 8, US4): a page of the report for the picked periods with
/// the supporting numbers open and the analysis blurred, and the way into Saku Plus. Nothing is made or shared.
struct PdfPreviewView: View {
    let summary: PdfReport.Summary
    let periodLabel: String
    /// The real analysis of the period: the score and the finding titles show, everything else stays hidden.
    var result: PeriodAnalysis.Analysis? = nil
    @ObservedObject private var plus = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var paywall: PlusReason?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 24)
            ScrollView {
                VStack(spacing: 18) {
                    page
                    PrimaryButton(title: L("Buka dengan Saku Plus")) { paywall = .pdfReport }
                    Text("Ekspor CSV tetap gratis.").font(.app(13)).foregroundStyle(Color.appTextTertiary)
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.large])

        .background(Color.appBackground)
        .plusOffer($paywall)
        // bought from here: the preview has done its job
        .onChange(of: plus.isPlus) { _, isPlus in if isPlus { dismiss() } }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Saku").font(.app(12, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    Spacer()
                    Text("Pratinjau").font(.app(11, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Color.appPrimary.opacity(0.12), in: Capsule())
                }
                Text("Laporan Keuangan").font(.app(24, weight: .bold)).tracking(-0.3)
                Text(periodLabel).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }

            HStack(spacing: 8) {
                box(L("Pemasukan"), summary.income, Color.appPrimary)
                box(L("Pengeluaran"), summary.expense, Color.appText)
                box(L("Selisih"), summary.income - summary.expense, summary.income - summary.expense < 0 ? Color.appError : Color.appPrimary)
            }

            if !summary.topCategories.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Kategori terbesar").font(.app(15, weight: .semibold))
                    let top = summary.topCategories.first?.1 ?? 1
                    ForEach(Array(summary.topCategories.prefix(3).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.0).font(.app(13)).foregroundStyle(Color.appBody).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(item.1.formattedAsCurrency()).font(.app(13, weight: .semibold)).monospacedDigit()
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Color.appPrimary).frame(width: proxy.size.width * (top > 0 ? item.1 / top : 0))
                            }
                            .frame(height: 5)
                            .background(Capsule().fill(Color.appBorder.opacity(0.4)))
                        }
                    }
                }
            }

            analysis
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 24))
    }

    /// The analysis and advice: placeholder lines under a blur, so nothing real is readable or made up for the user.
    private var analysis: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analisis dan saran").font(.app(15, weight: .semibold))
            if let result {
                if let score = result.score {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Skor kesehatan").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                        Text("\(score.value)").font(.app(28, weight: .light)).tracking(-1)
                        Text(score.label ?? L("Sementara")).font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    }
                }
                ForEach(result.findings.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(result.findings[index].kicker).font(.app(11)).foregroundStyle(Color.appTextSecondary)
                        Text(result.findings[index].title).font(.app(14, weight: .semibold))
                    }
                }
            }
            ZStack {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Pengeluaranmu periode ini naik dibanding periode sebelumnya, terutama di satu kategori.",
                             "Dua budget hampir habis sebelum periode berakhir. Pertimbangkan menaikkannya atau menahan pengeluaran.",
                             "Sisihkan selisih pemasukan ke dompet tabungan supaya tidak habis tanpa terasa."], id: \.self) { line in
                        Text(verbatim: line).font(.app(14)).foregroundStyle(Color.appBody)
                    }
                }
                .blur(radius: 6).accessibilityHidden(true)
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 18)).foregroundStyle(Color.appPrimary)
                        .frame(width: 40, height: 40).background(Color.appBackground, in: Circle())
                    Text("Analisis dan saran ada di Saku Plus").font(.app(13, weight: .medium)).foregroundStyle(Color.appText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func box(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.app(11)).foregroundStyle(Color.appTextSecondary)
            Text(value.formattedAsCurrency()).font(.app(14, weight: .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}
