import SwiftUI

/// The ways of recording that have a switch in Profil › Smart Tracker.
enum SmartWay: CaseIterable {
    case ai, reminder, siri

    var title: String {
        switch self {
        case .ai: return "AI"
        case .reminder: return L("Pengingat draf")
        case .siri: return "Siri"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .reminder: return "bell"
        case .siri: return "phone"
        }
    }
}

/// What is sent, removed, kept and how to delete it (design 1g). A sheet with a medium and a large detent, opened from the
/// agreement sheet and from Profil › Smart Tracker.
/// The four things to know about how Smart Tracker handles data: shared by the sheet (consent) and the page (settings).
private struct PrivacyPoints: View {
    /// icon, title, one-line summary, full text
    static var points: [(String, String, String, String)] {
        [("arrow.up.right", L("Apa yang dikirim"), L("Hanya teks. Tidak dipakai melatih AI."),
          L("Hanya teks: yang kamu ketik, ucapkan (diubah jadi teks), bagikan, atau baca dari gambar. Teks dikirim ke penyedia model bahasa untuk dibaca AI. Tidak dipakai melatih AI.")),
         ("lock", L("Apa yang dibuang di perangkat"), L("Nomor panjang dan kode OTP. Gambar mentah tidak pernah dikirim."),
          L("Nomor panjang (rekening, kartu) dan kode OTP dihapus sebelum teks dikirim. Gambar mentah tidak pernah dikirim.")),
         ("tray", L("Apa yang disimpan"), L("Transaksi yang kamu simpan, jatah AI, dan Ingatan."),
          L("Transaksi yang kamu simpan, hitungan jatah AI, dan Ingatan (kata kunci, kategori, dompet) selama AI menyala. Kalimat asli yang kamu ketik, ucapkan, atau bagikan, gambar yang kamu pilih beserta teks yang terbaca darinya, serta teks notifikasi dan Siri, tetap di HP sampai drafnya kamu simpan atau buang. Draf yang tidak kamu proses hilang sendiri setelah 30 hari. Tidak ada yang tercatat sebelum kamu ketuk Simpan.")),
         ("trash", L("Cara menghapus"), L("Profil, lalu Hapus akun."), L("Buka Profil, lalu Hapus akun. Datamu ikut terhapus."))]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 14) {
                        Image(systemName: point.0).font(.system(size: 20)).foregroundStyle(Color.appPrimary).frame(width: 24)
                        Text(point.1).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
                    }
                    Text(point.3).font(.app(15)).lineSpacing(4).foregroundStyle(Color.appBody).padding(.leading, 38)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.appDivider).frame(height: 1) }
            }
        }
    }
}

struct SmartTrackerPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Cara data diproses")).font(.app(20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Text(L("Selesai")).font(.app(17, weight: .semibold)).foregroundStyle(Color.appPrimary).frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).frame(minHeight: 52)
            ScrollView {
                PrivacyPoints().padding(.bottom, 34)
            }
            .sheetScrollSlack()
        }
        .background(Color.appBackground)
        .adaptiveSheet()
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

/// Profil › Smart Tracker › Cara data diproses, as a page of its own: the same section labels and rows as the Smart Tracker settings.
struct SmartTrackerPrivacyPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(L("Dikirim"))
                row("arrow.up.right", L("Apa yang dikirim"), L("Hanya teks. Tidak dipakai melatih AI."))
                row("lock", L("Apa yang dibuang di perangkat"), L("Nomor panjang, kode OTP, dan gambar mentah tidak ikut dikirim."))
                section(L("Disimpan"))
                row("tray", L("Apa yang disimpan"), L("Transaksi yang kamu simpan, jatah AI, dan Ingatan."))
                row("doc.text", L("Teks asli dan gambar"), L("Tetap di HP sampai kamu simpan atau buang draf. Draf hilang sendiri setelah 30 hari."))
                section(L("Hapus"))
                row("trash", L("Cara menghapus"), L("Profil, lalu Hapus akun. Datamu ikut terhapus."))
            }
            .padding(.top, 8).padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .navigationTitle(L("Cara data diproses"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesSmartButton()
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 6)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color.appText).frame(width: 28).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(16, weight: .semibold)).foregroundStyle(Color.appText)
                Text(detail).font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 10).frame(minHeight: 60, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // report the proposed width: placing in a narrower bounds wraps a row the height was not counted for
        let width = proposal.width ?? 320
        let size = arrange(width, subviews).size
        return CGSize(width: proposal.width == nil ? size.width : width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(bounds.width, subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// The one AI agreement (design 1a). "Setuju dan aktifkan AI" saves it on the account (and on the device right away);
/// "Nanti saja" leaves AI off, and the sheet opens again from the AI switch.
struct SmartTrackerConsentSheet: View {
    /// Whose agreement this is; it is saved on the profile so it follows the account to every device.
    let profileId: UUID?
    var onAgree: () -> Void
    /// Menu uji: shows the sheet without saving an agreement.
    var isPreview = false
    @Environment(\.dismiss) private var dismiss
    @State private var showsDetails = false
    @State private var height: CGFloat = 560

    private var promises: [(String, String)] {
        [("globe", L("Teks yang kamu masukkan dikirim ke penyedia model bahasa.")),
         ("lock", L("Nomor panjang (rekening, kartu) dan kode OTP dibuang di perangkat sebelum dikirim.")),
         ("camera.fill", L("Hanya teks yang dikirim, bukan gambar mentah."))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sparkles").font(.system(size: 28)).foregroundStyle(Color.appPrimary)
                .frame(width: 56, height: 56).background(Color.appPrimary.opacity(0.12), in: Circle())
            Text(L("Aktifkan AI untuk Smart Tracker")).font(.app(26, weight: .bold)).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(promises.enumerated()), id: \.offset) { _, promise in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: promise.0).font(.system(size: 20)).foregroundStyle(Color.appTextSecondary)
                            .frame(width: 24).padding(.top, 1)
                        Text(promise.1).font(.app(16)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(spacing: 4) {
                PrimaryButton(title: L("Setuju dan aktifkan AI"), action: agree)
                Button(action: decline) {
                    Text(L("Nanti saja")).font(.app(17, weight: .semibold)).foregroundStyle(Color.appText)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                Text(L("AI mati. Smart Tracker tetap jalan dengan aturan di perangkat."))
                    .font(.app(13)).lineSpacing(2).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    .padding(.top, -6)
                Button { showsDetails = true } label: {
                    Text(L("Cara data diproses")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Color.appText)
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { geo in
            Color.clear.onAppear { height = geo.size.height }.onChange(of: geo.size.height) { _, new in height = new }
        })
        .background(Color.appBackground)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .sheet(isPresented: $showsDetails) { SmartTrackerPrivacySheet() }
    }

    private func agree() {
        if isPreview { dismiss(); onAgree(); return }
        // agree now (works offline); the profile is updated in the background and retried at next launch
        SmartTrackerConsent.isGranted = true
        SmartTrackerConsent.since = Date()
        SmartTrackerConsent.promptSeen = true
        if let profileId {
            Task {
                try? await SupabaseSDK.recordSmartTrackerConsent(profileId: profileId)
                await DraftStore.shared.syncMemory()
            }
        }
        onAgree()
    }

    private func decline() {
        if !isPreview {
            SmartTrackerConsent.promptSeen = true
            if SmartTrackerConsent.isGranted {
                SmartTrackerConsent.isGranted = false
                if let profileId { Task { try? await SupabaseSDK.revokeSmartTrackerConsent(profileId: profileId) } }
            }
        }
        dismiss()
    }
}
