import SwiftUI

/// Profil › Saku Plus › Bantuan AI (design "Plus D Jatah AI" 12a): what is left this month, where it came from,
/// what it was used for. Sample numbers; test builds also get a picker for the levels.
struct AIQuotaView: View {
    @ObservedObject private var plus = PlusStore.shared
    @State private var level: AIQuota.Level = .normal
    @State private var paywall: PlusReason?
    @State private var showsReferral = false

    private var quota: AIQuota { AIQuota.sample(level, isPlus: plus.isPlus) }

    private var tint: Color {
        switch quota.level { case .normal: Color.appText; case .low: Color.appWarning; case .empty: Color.appError }
    }

    private var note: String {
        switch quota.level {
        case .normal: L("Terisi lagi 1 Nov.")
        case .low: L("Sisa %lld. Terisi lagi 1 Nov, 17 hari lagi.", quota.left)
        case .empty: L("Habis. Mengetik tetap jalan seperti biasa. Terisi lagi 1 Nov.")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Jatah AI").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                if PlusStore.isInternalBuild, !plus.isPlus { picker.padding(.top, 10) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sisa bulan ini").font(.app(14)).foregroundStyle(Color.appTextSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(quota.left)").font(.app(56, weight: .ultraLight)).tracking(-2).monospacedDigit().foregroundStyle(tint)
                        Text("/ \(quota.total)").font(.app(22, weight: .light)).foregroundStyle(Color.appTextTertiary)
                    }
                    HStack(spacing: 2) {
                        let filled = Int((Double(quota.left) / Double(quota.total) * 30).rounded())
                        ForEach(0..<30, id: \.self) { i in
                            Capsule().fill(i < filled ? (quota.level == .normal ? Color.appPrimary : tint) : Color.appFill).frame(height: 6)
                        }
                    }
                    .padding(.top, 8)
                    Text(note).font(.app(14)).foregroundStyle(quota.level == .normal || plus.isPlus ? Color.appTextSecondary : tint)
                        .padding(.top, 4).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18).stEnter(0)

                Divider().overlay(Color.appDivider).padding(.top, 22).padding(.bottom, 14)
                Text("Asal jatah").font(.app(15, weight: .semibold))
                VStack(spacing: 0) {
                    row(icon: plus.isPlus ? "crown" : "gift", title: plus.isPlus ? L("Saku Plus") : L("Gratis bulanan"),
                        sub: L("Setiap tanggal 1"), value: "+\(quota.base)")
                    row(icon: "person.2", title: L("Dari teman"), sub: L("1 teman bergabung · berlaku sampai 31 Okt"), value: "+\(quota.fromFriends)")
                }
                .padding(.top, 6)
                Divider().overlay(Color.appDivider).padding(.top, 12).padding(.bottom, 14)
                Text("Dipakai untuk").font(.app(15, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(quota.uses, id: \.label) { use in row(icon: use.icon, title: use.label, sub: nil, value: "\(use.count)", valueColor: Color.appText) }
                }
                .padding(.top, 6)
                Text("Mencatat dengan mengetik biasa tidak memakai jatah. Jatah hanya terpakai saat AI membaca teks bebas, foto struk, atau email.")
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, 12)

                if !plus.isPlus {
                    PrimaryButton(title: L("Tambah dengan Plus")) { paywall = .general }.padding(.top, 28)
                    Button { showsReferral = true } label: {
                        Text("Ajak teman, dapat +5").font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain).padding(.top, 8)
                }
                if PlusStore.isInternalBuild {
                    Text("Angka contoh sampai server siap.").font(.app(12)).foregroundStyle(Color.appTextTertiary).padding(.top, 10)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .hidesSmartButton()
        .plusOffer($paywall)
        .navigationDestination(isPresented: $showsReferral) { ReferralView().detailPage() }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach([(AIQuota.Level.normal, L("Gratis")), (.low, L("Hampir habis")), (.empty, L("Habis"))], id: \.1) { item in
                Button { level = item.0 } label: {
                    Text(item.1).font(.app(13, weight: .semibold)).foregroundStyle(level == item.0 ? Color.white : Color.appText)
                        .padding(.horizontal, 12).frame(height: 30).background(level == item.0 ? Color.appPrimary : Color.stChip, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(icon: String, title: String, sub: String?, value: String, valueColor: Color = Color.appPrimary) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(15)).foregroundStyle(Color.appText)
                if let sub { Text(sub).font(.app(13)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Text(value).font(.app(15)).monospacedDigit().foregroundStyle(valueColor)
        }
        .padding(.vertical, 10)
    }
}
