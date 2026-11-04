import SwiftUI

/// The ways of recording that have a switch in Profil › Smart Tracker.
enum SmartWay: CaseIterable {
    case ai, notification, siri

    var title: String {
        switch self {
        case .ai: return "AI"
        case .notification: return L("Notifikasi")
        case .siri: return "Siri"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "sparkles"
        case .notification: return "bell.badge"
        case .siri: return "waveform"
        }
    }
}

/// What is sent, removed, kept and how to delete it: the body of Profil › Smart Tracker › Cara data diproses.
struct SmartTrackerPrivacyContent: View {
    var points: [(String, String, String)] {
        [("arrow.up.right", L("Apa yang dikirim"),
          L("Hanya teks: yang kamu ketik, ucapkan (diubah jadi teks), bagikan, atau baca dari gambar. Teks dikirim ke penyedia model bahasa untuk dibaca AI. Tidak dipakai melatih AI.")),
         ("lock", L("Apa yang dibuang di perangkat"),
          L("Nomor panjang (rekening, kartu) dan kode OTP dihapus sebelum teks dikirim. Gambar mentah tidak pernah dikirim.")),
         ("tray", L("Apa yang disimpan"),
          L("Transaksi yang kamu simpan, hitungan jatah AI, dan Ingatan (kata kunci, kategori, dompet) selama AI menyala. Kalimat asli dihapus begitu draf jadi. Draf yang tidak kamu proses hilang sendiri setelah 30 hari. Tidak ada yang tercatat sebelum kamu ketuk Simpan.")),
         ("trash", L("Cara menghapus"), L("Buka Profil, lalu Hapus akun. Datamu ikut terhapus."))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: point.0)
                        .font(.system(size: 17))
                        .foregroundStyle(Color.appText)
                        .frame(width: 36, height: 36)
                        .background(Color.stChip, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(point.1)).font(.app(15, weight: .semibold))
                        Text(L(point.2)).font(.app(14)).lineSpacing(2).foregroundStyle(Color.appTextSecondary)
                    }
                }
            }
        }
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

    var body: some View {
        SmartSheet(tone: .consent, icon: "sparkles", title: L("Aktifkan AI untuk Smart Tracker"),
                   promises: [SmartPromise(icon: "globe", title: L("Teks dikirim ke AI"), detail: L("Teks yang kamu masukkan dikirim ke penyedia model bahasa.")),
                              SmartPromise(icon: "lock", title: L("Nomor panjang dibuang"), detail: L("Nomor panjang (rekening, kartu) dan kode OTP dibuang di perangkat sebelum dikirim.")),
                              SmartPromise(icon: "camera.fill", title: L("Bukan gambar mentah"), detail: L("Hanya teks yang dikirim, bukan gambar mentah."))],
                   extra: {
                       VStack(spacing: 6) {
                           Text(L("Kalau Nanti saja, AI mati. Smart Tracker tetap jalan dengan aturan di perangkat."))
                               .font(.app(13)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                           Button { showsDetails = true } label: {
                               Text(L("Cara data diproses")).font(.app(15, weight: .semibold)).foregroundStyle(Color.appPrimary)
                                   .frame(minHeight: 44)
                           }
                       }
                       .frame(maxWidth: .infinity).padding(.top, 14)
                   }) {
            SmartSheetFooter(primary: L("Setuju dan aktifkan AI"), secondary: L("Nanti saja"), onPrimary: agree, onSecondary: decline)
        }
        .sheet(isPresented: $showsDetails) {
            ScrollView { SmartTrackerPrivacyContent().padding(24) }
                .background(Color.appBackground)
                .presentationDetents([.medium, .large])
        }
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
