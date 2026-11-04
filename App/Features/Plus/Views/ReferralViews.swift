import SwiftUI

/// Profil › Ajak teman (design "Plus C Ajak Teman" 8a): the code, progress per friend, history and how it works.
/// Real data from the server (Fitur 2). A Plus account sees only the code and the share button: no counter and no
/// promise of +10, because Plus already has unlimited AI help (K7). Guests never get here (K6).
struct ReferralView: View {
    @ObservedObject private var plus = PlusStore.shared
    @State private var summary: ReferralSummary?
    @State private var failed = false
    @State private var copied = false
    @State private var entersCode = false

    private var shareText: String {
        guard let summary else { return "" }
        return L("Aku pakai Saku buat catat keuangan. Pakai kodeku %@ waktu daftar: %@", summary.code, summary.inviteLink)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ajak teman").font(.app(34, weight: .bold)).tracking(-0.4).foregroundStyle(Color.appText)
                if plus.isPlus {
                    Text(L("Bagikan kodemu ke temanmu.")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }

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
        .sheet(isPresented: $entersCode) { ReferralRedeemSheet { Task { await load() } } }
    }

    @ViewBuilder
    private func content(_ summary: ReferralSummary) -> some View {
        if !plus.isPlus {
            // design 1f: the permanent bonus, what each side gets, then the code
            VStack(alignment: .leading, spacing: 12) {
                Text(L("Bonus jatah permanen")).font(.app(15)).foregroundStyle(Color.appTextSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("+\(summary.reward)").font(.app(58, weight: .ultraLight)).tracking(-2).monospacedDigit().foregroundStyle(Color.appPrimary)
                    Text(L("dari maks. +40")).font(.app(17)).foregroundStyle(Color.appTextSecondary)
                }
                SegmentBar(value: Double(summary.reward) / Double(ReferralSummary.bonusCap), count: 40, height: 14, spacing: 3)
                Text(summary.isMaxed ? L("Bonus penuh. Jatah kamu 90 per bulan. Teman baru tetap dapat +10.") : L("Maks. +40. Jatah dasar 50, total maksimal 90."))
                    .font(.app(13)).lineSpacing(3).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16).stEnter(0)

            HStack(alignment: .top, spacing: 12) {
                rewardCard(L("Kamu dapat"), L("Setelah teman mencatat transaksi pertama."))
                rewardCard(L("Temanmu dapat"), L("Saat daftar dengan kodemu, setelah transaksi pertamanya."))
            }
            .padding(.top, 20).stEnter(1)
        }

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Kodemu")).font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Text(summary.code).font(.app(19, weight: .semibold)).tracking(1).monospacedDigit().foregroundStyle(Color.appText)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = summary.code
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Text(copied ? L("Tersalin") : L("Salin kode")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimaryText).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 64)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.appBorder, lineWidth: 1))
        .padding(.top, 16).stEnter(2)

        // an account that skipped the code at sign-up (or signed up before this existed) may still enter one
        if summary.canRedeem {
            Button { entersCode = true } label: { linkRow(L("Punya kode dari teman?"), trailing: "") }
                .buttonStyle(.plain).padding(.top, 14)
        }

        if !plus.isPlus {
            NavigationLink(destination: ReferralHistoryView(summary: summary).detailPage()) {
                linkRow(L("Riwayat ajakan"), trailing: summary.friends.isEmpty ? "" : "\(summary.friends.count)")
            }
            .buttonStyle(.plain).padding(.top, 14)
            NavigationLink(destination: ReferralHowView(shareText: shareText).detailPage()) { linkRow(L("Cara kerjanya"), trailing: "") }
                .buttonStyle(.plain)
        }

        ShareLink(item: shareText) {
            Label(L("Bagikan kode"), systemImage: "square.and.arrow.up")
                .font(.app(17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54).background(Color.appPrimary, in: Capsule())
        }
        .padding(.top, 28)
    }

    private func rewardCard(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            Text(verbatim: "+10").font(.app(28, weight: .light)).foregroundStyle(Color.appPrimary)
            Text(detail).font(.app(13)).lineSpacing(3).foregroundStyle(Color.appBody).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16))
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
                                    Text(verbatim: "+10").font(.app(15)).monospacedDigit().foregroundStyle(Color.appPrimary)
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
        (L("Transaksi pertama tercatat"), L("Begitu temanmu mencatat transaksi pertamanya, +10 bantuan AI langsung masuk ke akunmu, dan temanmu juga dapat +10.")),
    ] }

    private var rules: [(String, String)] { [
        ("gift", L("+10 bantuan AI per teman, maksimal +40. Bonusnya tidak hilang tiap bulan.")),
        ("person.badge.plus", L("Hanya untuk akun baru. Satu akun hanya bisa memakai satu kode.")),
        ("eye.slash", L("Nama temanmu hanya tampil di riwayat bila ia mengizinkan.")),
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

/// "Punya kode dari teman?" from Ajak teman: for an account that did not enter a code at sign-up.
struct ReferralRedeemSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var message: String?
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 24)
            VStack(alignment: .leading, spacing: 14) {
                Text("Punya kode dari teman?").font(.app(22, weight: .bold)).tracking(-0.3)
                Text("Kode hanya bisa dipakai sekali, oleh akun baru yang belum mencatat transaksi.")
                    .font(.app(14)).foregroundStyle(Color.appTextSecondary).fixedSize(horizontal: false, vertical: true)
                TextField("", text: $code, prompt: Text("Kode").foregroundStyle(Color.appTextTertiary))
                    .font(.app(22, weight: .medium)).tracking(3)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(.horizontal, 14).frame(height: 52)
                    .background(Color.appFill, in: RoundedRectangle(cornerRadius: 14))
                    .onChange(of: code) { _, value in
                        let cleaned = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if cleaned != value { code = cleaned }
                        message = nil
                    }
                if let message { Text(message).font(.app(13)).foregroundStyle(Color.appError).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 24)
        }
        .filterSheet {
            PrimaryButton(title: L("Pakai kode"), isLoading: isChecking, isEnabled: code.count == 6) { redeem() }
        }

        .background(Color.appBackground)
    }

    private func redeem() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                try await SupabaseSDK.redeemReferralCode(code)
                onDone()
                dismiss()
            } catch {
                message = ReferralFailure.message(for: error)
            }
        }
    }
}
