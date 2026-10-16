import SwiftUI

/// Why the paywall is shown: a limit reached or a Plus feature tapped (design "Plus A Penawaran", TC 1, 23, 24).
enum PlusReason: Identifiable, Equatable {
    case moneyWallets, investmentWallets, categories(CategoryType), budgets, notifications, receiptPhoto, general

    var id: String {
        switch self {
        case .categories(let type): "categories-\(type.rawValue)"
        default: "\(self)"
        }
    }

    /// The benefit the user is reaching for (design "Plus A Penawaran").
    var title: String {
        switch self {
        case .moneyWallets: L("Dompet tanpa batas")
        case .investmentWallets: L("Investasi tanpa batas")
        case .categories: L("Kategori tanpa batas")
        case .budgets: L("Budget tanpa batas")
        case .notifications: L("Catat dari notifikasi")
        case .receiptPhoto: L("Catat dari foto struk")
        case .general: L("Catat lebih sedikit")
        }
    }

    var message: String {
        switch self {
        case .moneyWallets: L("Dengan Plus, tambah dompet sebanyak yang kamu perlukan. Atau arsipkan yang jarang dipakai.")
        case .investmentWallets: L("Plus membuka Dompet Investasi tanpa batas, semua masuk ke Total kekayaan.")
        case .categories: L("Dengan Plus, buat kategori sesuai caramu. Atau sembunyikan yang tidak terpakai.")
        case .budgets: L("Dengan Plus, atur budget untuk setiap kategori. Atau ubah budget yang ada.")
        case .notifications: L("Notifikasi BCA, GoPay, dan lainnya langsung jadi draf. Kamu tinggal periksa dan simpan.")
        case .receiptPhoto: L("Ambil foto struk atau screenshot, Saku mengisi jumlah, toko, dan tanggalnya.")
        case .general: L("Saku Plus membuka semua batas dan mencatat otomatis dari bank, struk, dan email.")
        }
    }

    /// The quiet second action, only where the user can make room instead.
    var makeRoomTitle: String? {
        switch self {
        case .moneyWallets, .investmentWallets: L("Atur dompet dulu")
        case .categories: L("Atur kategori dulu")
        case .budgets: L("Atur budget dulu")
        default: nil
        }
    }
}

/// Sample prices until the App Store products exist (Epic 11 US3). Not final.
enum PlusPricing {
    static let yearly = "Rp149.000"
    static let yearlyStrike = "Rp228.000"
    static let yearlyPerMonth = "Rp12.417"
    static let monthly = "Rp19.000"
    static let launchUntil = "31 Okt 2026"
}

/// Full-screen paywall (design 1g). Buying needs StoreKit, so the button says it is coming; the loading,
/// failed and buying states and the result screens come with US3.
struct PlusPaywallView: View {
    let reason: PlusReason
    @Environment(\.dismiss) private var dismiss
    @State private var yearly = true
    @State private var showsSoon = false
    /// A sheet at its short height: the same content, smaller (design 1h).
    @State private var compact = false

    private var price: String { yearly ? "\(PlusPricing.yearly)/\(L("tahun"))" : "\(PlusPricing.monthly)/\(L("bulan"))" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Saku Plus").font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.appTextSecondary)
                            .frame(width: 32, height: 32).background(Color.stChip, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Tutup"))
                }
                Text(reason.title)
                    .font(.app(compact ? 24 : 30, weight: .bold)).tracking(-0.5).foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, compact ? 8 : 14).stEnter(0)
                Text(reason.message)
                    .font(.app(15)).foregroundStyle(Color.appTextSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).stEnter(1)

                PaywallHero(compact: compact).padding(.top, compact ? 12 : 20).stEnter(2)
                if !compact {
                    Text("Juga: laporan PDF dan lebih banyak bantuan AI")
                        .font(.app(12)).foregroundStyle(Color.appTextSecondary).frame(maxWidth: .infinity).padding(.top, 12)
                    HStack(spacing: 14) {
                        Label(L("Data tetap milikmu"), systemImage: "checkmark.shield")
                        Label(L("Batalkan kapan saja"), systemImage: "xmark.circle")
                    }
                    .font(.app(12)).foregroundStyle(Color.appTextSecondary).frame(maxWidth: .infinity).padding(.top, 12)
                }

                if PlusStore.isInternalBuild {
                    Text(verbatim: "HARGA CONTOH · BELUM FINAL")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Color.appWarning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.appWarning, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        .padding(.top, 24)
                }

                HStack(spacing: 10) {
                    planCard(name: L("1 tahun"), strike: PlusPricing.yearlyStrike, price: PlusPricing.yearly,
                             per: L("Setara %@/bln", PlusPricing.yearlyPerMonth), best: true, selected: yearly) { yearly = true }
                    planCard(name: L("Bulanan"), strike: nil, price: PlusPricing.monthly, per: L("per bulan"), best: false, selected: !yearly) { yearly = false }
                }
                .padding(.top, PlusStore.isInternalBuild ? 12 : (compact ? 16 : 28))
                Text(L("Harga peluncuran sampai %@", PlusPricing.launchUntil))
                    .font(.app(12)).foregroundStyle(Color.appTextSecondary).padding(.top, 10)

                PrimaryButton(title: L("Coba gratis 7 hari")) { showsSoon = true }.padding(.top, 16)
                Text(L("Gratis 7 hari, lalu %@. Batalkan kapan saja di Pengaturan iPhone › Apple ID.", price))
                    .font(.app(13)).foregroundStyle(Color.appTextSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.top, 10)

                if let second = reason.makeRoomTitle {
                    Button { dismiss() } label: {
                        Text(second).font(.app(15, weight: .semibold)).foregroundStyle(Color.appText)
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.plain).padding(.top, 8)
                }

                Text(L("Langganan diperpanjang otomatis %@ kecuali dimatikan minimal 24 jam sebelum periode berakhir. Pembayaran ditagih ke Apple ID. Kelola atau batalkan di Pengaturan App Store.",
                       yearly ? L("setiap tahun sebesar %@", PlusPricing.yearly) : L("setiap bulan sebesar %@", PlusPricing.monthly)))
                    .font(.app(11)).foregroundStyle(Color.appTextTertiary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity).padding(.top, 12)
                HStack(spacing: 16) {
                    Text("Syarat"); Text("Kebijakan Privasi"); Text("Pulihkan pembelian")
                }
                .font(.app(12, weight: .medium)).foregroundStyle(Color.appTextSecondary).frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Color.appBackground)
        .onGeometryChange(for: Bool.self) { $0.size.height < 650 } action: { compact = $0 }
        .presentationDetents([.fraction(0.56), .large])
        .presentationDragIndicator(.visible)
        .alert(L("Pembelian segera hadir"), isPresented: $showsSoon) { Button("OK", role: .cancel) {} } message: {
            Text("Saku Plus belum bisa dibeli. Kami kabari saat sudah dibuka.")
        }
    }

    private func planCard(name: String, strike: String?, price: String, per: String, best: Bool, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.app(14)).foregroundStyle(Color.appTextSecondary)
                Text(strike ?? " ").font(.app(13)).strikethrough(strike != nil).foregroundStyle(Color.appTextTertiary)
                Text(price).font(.app(26, weight: .light)).tracking(-0.6).foregroundStyle(Color.appText)
                Text(per).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 22).padding([.horizontal, .bottom], 16)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.appText : Color.appBorder.opacity(0.6), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appBackground)
                        .frame(width: 20, height: 20).background(Color.appText, in: Circle()).padding(14)
                }
            }
            .overlay(alignment: .topLeading) {
                if best {
                    Text("Paling hemat").font(.app(11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Color.appPrimary, in: Capsule())
                        .offset(x: 14, y: -10)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selected)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// The paywall's story: eight short scenes that replace a feature list. Each shows what arrives (a notification, a
/// photo, an email) and then what it became. Swipe or tap a dot to move; it also advances by itself every 4.8 s.
private struct PaywallHero: View {
    let compact: Bool

    private struct Scene {
        let badge: String, badgeColor: Color, notifTitle: String, notifBody: String
        let icon: String, rowTitle: String, rowSub: String, amount: String, caption: String
    }

    private let scenes: [Scene] = [
        Scene(badge: "BCA", badgeColor: Color(light: 0x0060AF, dark: 0x0060AF), notifTitle: "BCA mobile", notifBody: "Debit Rp45.000 · KOPI KENANGAN",
              icon: "cup.and.saucer", rowTitle: "Kopi Kenangan", rowSub: L("Makan · BCA · dari notifikasi"), amount: "−Rp45.000", caption: L("Notifikasi bank jadi draf, tinggal simpan")),
        Scene(badge: "camera", badgeColor: Color(light: 0x111111, dark: 0x3A3A3C), notifTitle: L("Foto struk"), notifBody: "IMG_2041.jpg · Indomaret",
              icon: "cart", rowTitle: "Indomaret", rowSub: L("Belanja · GoPay · dari foto struk"), amount: "−Rp87.500", caption: L("Foto struk dibaca otomatis")),
        Scene(badge: "envelope", badgeColor: Color(light: 0x6E6E73, dark: 0x636366), notifTitle: L("Diteruskan ke Saku"), notifBody: "Tokopedia · Pesanan selesai",
              icon: "shippingbox", rowTitle: "Tokopedia", rowSub: L("Belanja · BCA · dari email"), amount: "−Rp249.000", caption: L("Teruskan email, draf siap disimpan")),
        Scene(badge: "infinity", badgeColor: Color.appPrimary, notifTitle: L("Dompet ke-6"), notifBody: L("Batas gratis 5 dompet"),
              icon: "wallet.pass", rowTitle: L("Tabungan liburan"), rowSub: L("Dompet baru · tanpa batas"), amount: "Rp0", caption: L("Dompet, kategori, budget tanpa batas")),
        Scene(badge: "sparkles", badgeColor: Color.appPrimary, notifTitle: L("Catat cepat"), notifBody: "makan siang 35rb, parkir 5rb",
              icon: "sparkles", rowTitle: L("2 transaksi terbaca"), rowSub: L("Makan · Transport"), amount: "−Rp40.000", caption: L("Bantuan AI tanpa batas")),
        Scene(badge: "doc.richtext", badgeColor: Color(light: 0x111111, dark: 0x3A3A3C), notifTitle: L("Laporan Oktober"), notifBody: L("PDF · 2 halaman · siap"),
              icon: "doc.richtext", rowTitle: L("Laporan Okt 2026"), rowSub: L("Ringkasan bulanan · siap dibagikan"), amount: "", caption: L("Laporan PDF bulanan")),
        Scene(badge: "square.and.arrow.up", badgeColor: Color(light: 0x111111, dark: 0x3A3A3C), notifTitle: L("Ekspor data"), notifBody: L("CSV · semua transaksi"),
              icon: "checkmark.shield", rowTitle: L("Datamu tetap ada"), rowSub: L("Juga saat Plus berhenti"), amount: "", caption: L("Data tetap milikmu")),
        Scene(badge: "gearshape", badgeColor: Color(light: 0x6E6E73, dark: 0x636366), notifTitle: "App Store", notifBody: L("Langganan · Saku Plus"),
              icon: "xmark.circle", rowTitle: L("Batalkan langganan"), rowSub: L("Dua ketukan, tanpa biaya"), amount: "", caption: L("Batalkan kapan saja")),
    ]

    @State private var index = 0
    @State private var showsResult = false
    /// Changes when the user moves the hero, so the 4.8 s timer starts over.
    @State private var restart = 0

    private var height: CGFloat { compact ? 116 : 200 }
    private var scale: CGFloat { compact ? 0.62 : 1.1 }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                canvas
                    .frame(width: proxy.size.width / scale, height: height / scale)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: height)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.width < -30 { go(index + 1) } else if value.translation.width > 30 { go(index - 1) }
            })
            HStack(spacing: 4) {
                ForEach(scenes.indices, id: \.self) { i in
                    Button { go(i) } label: {
                        Capsule().fill(i <= index ? Color.appPrimary : Color.appBorder.opacity(0.6)).frame(width: 18, height: 3)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: restart) {
            // each scene: what arrives first, then what it became (4.8 s per scene)
            while !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.4)) { showsResult = false }
                try? await Task.sleep(for: .seconds(2.2))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.4)) { showsResult = true }
                try? await Task.sleep(for: .seconds(2.6))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.3)) { index = (index + 1) % scenes.count }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(scenes[index].caption)
    }

    private func go(_ target: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { index = (target + scenes.count) % scenes.count; showsResult = false }
        restart += 1
    }

    /// One scene drawn on a 150 pt tall canvas; the caller scales it.
    private var canvas: some View {
        let scene = scenes[index]
        return ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color.stChip)
            if showsResult {
                HStack(spacing: 12) {
                    Image(systemName: scene.icon).font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene.rowTitle).font(.app(15)).foregroundStyle(Color.appText)
                        Text(scene.rowSub).font(.app(12)).foregroundStyle(Color.appTextSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(scene.amount).font(.app(15)).monospacedDigit().foregroundStyle(Color.appText)
                }
                .padding(.horizontal, 18).transition(.opacity.combined(with: .offset(y: 14)))
            } else {
                HStack(spacing: 10) {
                    badge(scene)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(scene.notifTitle).font(.app(12, weight: .semibold)).foregroundStyle(Color.appText)
                        Text(scene.notifBody).font(.app(12)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text("sekarang").font(.app(11)).foregroundStyle(Color.appTextTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 16)
                .transition(.opacity.combined(with: .offset(y: -14)))
            }
            VStack {
                Spacer()
                Text(scene.caption).font(.app(13, weight: .semibold)).foregroundStyle(Color.appText).padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder private func badge(_ scene: Scene) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(scene.badgeColor)
            if scene.badge == "BCA" {
                Text(verbatim: "BCA").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            } else {
                Image(systemName: scene.badge).font(.system(size: 14)).foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
    }
}

extension View {
    /// Presents the Plus paywall for `reason` (nil = closed): full screen from Profil, a sheet over the
    /// screen the user came from when a limit or a Plus feature opened it (design 1g and 1h).
    func plusOffer(_ reason: Binding<PlusReason?>) -> some View {
        let full = Binding<PlusReason?>(get: { reason.wrappedValue == .general ? .general : nil }, set: { reason.wrappedValue = $0 })
        let sheet = Binding<PlusReason?>(get: { reason.wrappedValue == .general ? nil : reason.wrappedValue }, set: { reason.wrappedValue = $0 })
        return fullScreenCover(item: full) { PlusPaywallView(reason: $0) }
            .sheet(item: sheet) { PlusPaywallView(reason: $0) }
    }
}
