import SwiftUI

/// The four ways of recording, as chips and as switches.
enum SmartWay: CaseIterable {
    case quick, notification, share, siri

    var title: String {
        switch self {
        case .quick: return L("Catat cepat")
        case .notification: return L("Notifikasi bank")
        case .share: return L("Bagikan teks")
        case .siri: return "Siri"
        }
    }

    var icon: String {
        switch self {
        case .quick: return "sparkles"
        case .notification: return "bell.badge"
        case .share: return "square.and.arrow.up"
        case .siri: return "waveform"
        }
    }
}

/// What Smart Tracker is and how data is used: the body of the first-time agreement and of
/// Profil › Smart Tracker › Cara data diproses.
struct SmartTrackerPrivacyContent: View {
    private var points: [(String, String, String)] {
        [("iphone", L("Diproses di HP-mu"), L("Kalimat, notifikasi, dan tulisan di gambar dibaca langsung di perangkat ini. Gambarnya tidak disimpan.")),
         ("icloud.and.arrow.up", L("Server hanya bila perlu"),
          L("Kalau kalimatnya sulit dipahami, Saku mengirim teksnya saja, tanpa saldo atau nomor rekening. Teks itu tidak disimpan dan tidak dipakai melatih AI.")),
         ("clock.badge.checkmark", L("Tidak disimpan lama"),
          L("Kalimat asli langsung dihapus begitu draf jadi. Draf yang tidak kamu proses hilang sendiri setelah 30 hari.")),
         ("arrow.triangle.2.circlepath", L("Ingatan ikut ke semua perangkatmu"),
          L("Pilihan yang diingat Saku (kata kunci, kategori, dompet, dan berapa kali dipakai) disimpan di server supaya ikut ke perangkat lain. Bukan kalimat aslinya, bukan nominalnya. Mode tamu hanya di perangkat ini.")),
         ("hand.tap", L("Kamu yang menentukan"), L("Tidak ada yang tercatat sebelum kamu ketuk Simpan."))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Cukup satu kalimat, Saku yang menyusun transaksinya. Kamu tinggal cek, lalu simpan."))
                .font(.app(16)).lineSpacing(3).foregroundStyle(Color.appBody)
            SmartWayChips(items: SmartWay.allCases.map { ($0.icon, $0.title) })
                .padding(.top, 16)
            Text(L("Soal datamu"))
                .font(.app(13, weight: .semibold)).foregroundStyle(Color.appTextSecondary).padding(.top, 22)
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
            .padding(.top, 12)
        }
    }
}

/// Small rounded chips that wrap onto several lines.
struct SmartWayChips: View {
    let items: [(icon: String, text: String)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.icon).font(.system(size: 13)).foregroundStyle(Color.stGreen)
                    Text(L(item.text)).font(.app(13, weight: .medium))
                }
                .padding(.leading, 9).padding(.trailing, 12).frame(height: 30)
                .background(Color.stChip, in: Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 320, subviews).size
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

/// First-time agreement (design 2a). "Aktifkan" saves it on the account (and on the device right away).
struct SmartTrackerConsentSheet: View {
    /// Whose agreement this is; it is saved on the profile so it follows the account to every device.
    let profileId: UUID?
    var onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.stGreen)
                        .frame(width: 52, height: 52)
                        .background(Color.stSuccessBg, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, 20)
                    Text("Smart Tracker").font(.app(28, weight: .bold)).tracking(-0.5).padding(.top, 14)
                    SmartTrackerPrivacyContent().padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            VStack(spacing: 4) {
                Text(L("Bisa dimatikan kapan saja di Profil › Smart Tracker"))
                    .font(.app(13)).foregroundStyle(Color.appTextTertiary).padding(.bottom, 8)
                Button {
                    // agree now (works offline); the profile is updated in the background and retried at next launch
                    SmartTrackerConsent.isGranted = true
                    SmartTrackerConsent.since = Date()
                    if let profileId {
                        Task {
                            try? await SupabaseSDK.recordSmartTrackerConsent(profileId: profileId)
                            // the agreement above also covers Ingatan on the server; guests stay on the device
                            if !DraftStore.shared.isGuest {
                                try? await SupabaseSDK.recordMemorySyncConsent(profileId: profileId)
                                await DraftStore.shared.syncMemory()
                            }
                        }
                    }
                    onAgree()
                } label: {
                    Text(L("Aktifkan Smart Tracker"))
                        .font(.app(17, weight: .semibold)).foregroundStyle(Color.appBackground)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Color.appText, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                Button(L("Nanti saja")) { dismiss() }
                    .font(.app(16)).foregroundStyle(Color.appTextSecondary)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .padding(.horizontal, 24).padding(.bottom, 12).padding(.top, 12)
            .background(Color.appBackground)
        }
        .background(Color.appBackground)
        .presentationDetents([.large])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(38)
        .presentationDragIndicator(.visible)
    }
}

/// Asked once to people who agreed to Smart Tracker before Ingatan could live on the server (and again after a week
/// if they choose "Nanti saja"). Until they agree, Ingatan stays on the device.
struct MemorySyncConsentSheet: View {
    let profileId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 24)).foregroundStyle(Color.stGreen)
                .frame(width: 52, height: 52).background(Color.stSuccessBg, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 28)
            Text("Ingatan ikut ke semua perangkatmu").font(.app(24, weight: .bold)).tracking(-0.4).padding(.top, 14)
            Text(L("Saku akan menyimpan pilihan yang diingatnya di server, supaya kategori dan dompet favoritmu tetap terisi saat ganti HP atau memakai Saku di perangkat lain."))
                .font(.app(16)).lineSpacing(3).foregroundStyle(Color.appBody).padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Yang disimpan: kata kunci, kategori, dompet, dan berapa kali dipakai."), systemImage: "checkmark")
                Label(L("Tidak disimpan: kalimat aslinya dan nominalnya."), systemImage: "xmark")
                Label(L("Bisa dimatikan kapan saja di Profil › Smart Tracker."), systemImage: "gearshape")
            }
            .font(.app(14)).foregroundStyle(Color.appTextSecondary).padding(.top, 16)
            Spacer(minLength: 20)
            Button {
                guard let profileId else { dismiss(); return }
                isSaving = true
                Task {
                    try? await SupabaseSDK.recordMemorySyncConsent(profileId: profileId)
                    await DraftStore.shared.syncMemory()
                    isSaving = false
                    dismiss()
                }
            } label: {
                ZStack {
                    if isSaving { ProgressView().tint(Color.appBackground) } else { Text(L("Aktifkan")) }
                }
                .font(.app(17, weight: .semibold)).foregroundStyle(Color.appBackground)
                .frame(maxWidth: .infinity).frame(height: 52).background(Color.appText, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            Button(L("Nanti saja")) {
                SmartTrackerMemorySync.declinedAt = Date()
                dismiss()
            }
            .font(.app(16)).foregroundStyle(Color.appTextSecondary)
            .frame(maxWidth: .infinity).frame(height: 44)
        }
        .padding(.horizontal, 24).padding(.bottom, 12)
        .presentationDetents([.height(520)])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }
}
