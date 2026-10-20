import SwiftUI

/// Profil › Ajak teman (design "Plus C Ajak Teman" 8a): the code, progress per friend, history and how it works.
/// Real data from the server (Fitur 2). A Plus account sees only the code and the share button: no counter and no
/// promise of +5, because Plus already has unlimited AI help (K7). Guests never get here (K6).
struct ReferralView: View {
    @ObservedObject private var plus = PlusStore.shared
    @State private var summary: ReferralSummary?
    @State private var failed = false
    @State private var copied = false

    private var shareText: String {
        guard let summary else { return "" }
        return L("Aku pakai Saku buat catat keuangan. Pakai kodeku %@ waktu daftar: %@", summary.code, summary.inviteLink)
    }

    private func progressLine(_ summary: ReferralSummary) -> String { L("%lld dari %lld teman bulan ini", summary.thisMonth, ReferralSummary.monthlyLimit) }

    private func note(_ summary: ReferralSummary) -> String {
        if summary.isMaxed { return L("Batas +20 bulan ini sudah tercapai. Teman tetap bisa memakai kodemu; hadiah berikutnya mulai %@.", nextReset) }
        if summary.waiting > 0 { return L("%lld teman menunggu transaksi pertama. Bisa tambah +%lld lagi bulan ini.", summary.waiting, 20 - summary.reward) }
        if summary.thisMonth > 0 { return L("Bisa tambah +%lld lagi bulan ini.", 20 - summary.reward) }
        return L("Belum ada teman bulan ini. Hadiah terisi lagi setiap tanggal 1.")
    }

    /// "1 Nov": when the monthly count starts again.
    private var nextReset: String {
        let first = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())).flatMap {
            Calendar.current.date(byAdding: .month, value: 1, to: $0)
        } ?? Date()
        let format = DateFormatter(); format.locale = AppLanguage.locale; format.dateFormat = "d MMM"
        return format.string(from: first)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ajak teman").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                Text(plus.isPlus ? L("Bagikan kodemu ke temanmu.") : L("Setiap teman yang mencatat transaksi pertama menambah +5 bantuan AI untukmu."))
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true).padding(.top, 8)

                if let summary {
                    content(summary)
                } else if failed {
                    ErrorStateView(message: L("Halaman ini belum bisa dimuat.")) { Task { await load() } }.padding(.top, 40)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .hidesSmartButton()
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ summary: ReferralSummary) -> some View {
        VStack(spacing: 6) {
            Text("Kode kamu").font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Text(summary.code).font(.app(34, weight: .light)).tracking(4).monospacedDigit().foregroundStyle(Color.appText)
            Button {
                UIPasteboard.general.string = summary.code
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? L("Tersalin") : L("Salin kode"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.app(14, weight: .semibold)).foregroundStyle(Color.appPrimary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 20))
        .padding(.top, 22).stEnter(0)

        if !plus.isPlus {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(progressLine(summary)).font(.app(15))
                    Spacer(minLength: 12)
                    Text(L("+%lld jatah AI", summary.reward)).font(.app(15)).monospacedDigit()
                        .foregroundStyle(summary.thisMonth > 0 ? Color.appPrimary : Color.appTextSecondary)
                }
                HStack(spacing: 6) {
                    ForEach(0..<ReferralSummary.monthlyLimit, id: \.self) { i in
                        Capsule().fill(i < summary.thisMonth ? Color.appPrimary : Color.appFill).frame(height: 6)
                    }
                }
                Text(note(summary)).font(.app(13)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 24)

            NavigationLink(destination: ReferralHistoryView(summary: summary).detailPage()) {
                linkRow(L("Riwayat ajakan"), trailing: summary.friends.isEmpty ? "" : "\(summary.friends.count)")
            }
            .buttonStyle(.plain).padding(.top, 22)
            NavigationLink(destination: ReferralHowView(shareText: shareText).detailPage()) { linkRow(L("Cara kerjanya"), trailing: "") }
                .buttonStyle(.plain)
        }

        ShareLink(item: shareText) {
            Label(L("Bagikan kode"), systemImage: "square.and.arrow.up")
                .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54).background(Color.appPrimary, in: Capsule())
        }
        .padding(.top, 28)
        if !plus.isPlus {
            Text("Hadiah masuk saat temanmu mencatat transaksi pertama. Maksimal +20 per bulan.")
                .font(.app(12)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.top, 10)
        }
    }

    private func load() async {
        failed = false
        do { summary = try await SupabaseSDK.fetchReferralSummary() } catch { if summary == nil { failed = true } }
    }

    private func linkRow(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.app(16)).foregroundStyle(Color.appText)
            Spacer()
            Text(trailing).font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.trailing, 8)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextTertiary)
        }
        .padding(.vertical, 13).contentShape(Rectangle())
    }
}

/// Riwayat ajakan: per month, friends with their status. A friend's name shows only when they allow it.
struct ReferralHistoryView: View {
    let summary: ReferralSummary

    private var months: [String] {
        var seen: [String] = []
        for friend in summary.friends where !seen.contains(friend.month) { seen.append(friend.month) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Riwayat ajakan").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                if summary.friends.isEmpty {
                    Text("Belum ada teman yang memakai kodemu.").font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.top, 20)
                }
                ForEach(months, id: \.self) { month in
                    Text(month).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.top, 24).padding(.bottom, 4)
                    ForEach(summary.friends.filter { $0.month == month }) { friend in
                        HStack(spacing: 14) {
                            Text(String(friend.name.prefix(1))).font(.app(15, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
                                .frame(width: 36, height: 36).background(Color.stChip, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(friend.name).font(.app(15)).foregroundStyle(friend.name == L("Teman") ? Color.appTextSecondary : Color.appText).lineLimit(1)
                                Text(friend.joined.map { L("Berhasil · %@", $0) } ?? L("Menunggu transaksi pertama"))
                                    .font(.app(13)).foregroundStyle(Color.appTextSecondary)
                            }
                            Spacer(minLength: 8)
                            if friend.joined != nil {
                                if friend.counts {
                                    Text(verbatim: "+5").font(.app(15)).monospacedDigit().foregroundStyle(Color.appPrimary)
                                } else {
                                    Text("Di atas batas").font(.app(12)).foregroundStyle(Color.appTextTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .hidesSmartButton()
    }
}

/// Cara kerjanya (design 8c): three numbered steps, then the rules.
struct ReferralHowView: View {
    let shareText: String

    private var steps: [(String, String)] { [
        (L("Bagikan kodemu"), L("Kirim kode atau tautan lewat WhatsApp, pesan, atau aplikasi apa saja.")),
        (L("Temanmu mendaftar"), L("Ia memasukkan kodemu saat membuat akun Saku. Langkah ini opsional untuknya.")),
        (L("Transaksi pertama tercatat"), L("Begitu temanmu mencatat transaksi pertamanya, +5 bantuan AI langsung masuk ke akunmu.")),
    ] }

    private var rules: [(String, String)] { [
        ("gift", L("+5 bantuan AI per teman, maksimal +20 setiap bulan.")),
        ("person.badge.plus", L("Hanya untuk akun baru. Satu akun hanya bisa memakai satu kode.")),
        ("eye.slash", L("Nama temanmu hanya tampil di riwayat bila ia mengizinkan.")),
        ("calendar", L("Hitungan bulanan mulai lagi setiap tanggal 1.")),
    ] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cara kerjanya").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 16) {
                            Text("\(i + 1)").font(.app(30, weight: .ultraLight)).monospacedDigit().frame(width: 28)
                                .foregroundStyle(i == steps.count - 1 ? Color.appPrimary : Color.appText)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.0).font(.app(16, weight: .semibold))
                                Text(step.1).font(.app(14)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.bottom, 22)
                        }
                        .stEnter(i)
                    }
                }
                .padding(.top, 20)
                Divider().overlay(Color.appDivider).padding(.top, 4).padding(.bottom, 14)
                Text("Ketentuan").font(.app(15, weight: .semibold))
                ForEach(rules, id: \.0) { rule in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: rule.0).font(.system(size: 16)).foregroundStyle(Color.appTextSecondary).frame(width: 24).padding(.top, 2)
                        Text(rule.1).font(.app(14)).foregroundStyle(Color.appBody).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
                ShareLink(item: shareText) {
                    Label(L("Bagikan kode"), systemImage: "square.and.arrow.up")
                        .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 54).background(Color.appPrimary, in: Capsule())
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .hidesSmartButton()
    }
}
