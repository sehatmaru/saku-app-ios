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
    /// Counts plan changes: the chosen price pulses once on each.
    @State private var pulse = 0
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
                             per: L("Setara %@/bln", PlusPricing.yearlyPerMonth), best: true, selected: yearly) { yearly = true; pulse += 1 }
                    planCard(name: L("Bulanan"), strike: nil, price: PlusPricing.monthly, per: L("per bulan"), best: false, selected: !yearly) { yearly = false; pulse += 1 }
                }
                .padding(.top, PlusStore.isInternalBuild ? 12 : (compact ? 16 : 28)).stEnter(3)
                Text(L("Harga peluncuran sampai %@", PlusPricing.launchUntil))
                    .font(.app(12)).foregroundStyle(Color.appTextSecondary).padding(.top, 10)

                PrimaryButton(title: L("Coba gratis 7 hari")) { showsSoon = true }.padding(.top, compact ? 12 : 16).stEnter(4)
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
        .background(Color.paywallSurface)
        .presentationBackground(Color.paywallSurface)
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
                // the chosen price pulses once each time the plan changes
                Text(price).font(.app(26, weight: .light)).tracking(-0.6).foregroundStyle(Color.appText)
                    .keyframeAnimator(initialValue: 1.0, trigger: selected ? pulse : -1) { content, scale in
                        content.scaleEffect(scale, anchor: .leading)
                    } keyframes: { _ in
                        CubicKeyframe(1.04, duration: 0.21)
                        CubicKeyframe(1.0, duration: 0.21)
                    }
                Text(per).font(.app(13)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, compact ? 14 : 22).padding([.horizontal, .bottom], compact ? 14 : 16)
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? Color.appText : Color.appBorder.opacity(0.6), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.paywallSurface)
                        .frame(width: 20, height: 20).background(Color.appText, in: Circle()).padding(14)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                if best {
                    Text("Paling hemat").font(.app(11, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3).background(Color.appPrimary, in: Capsule())
                        .overlay { Shine().clipShape(Capsule()) }
                        .offset(x: 14, y: -10)
                }
            }
            .animation(.spring(duration: 0.32, bounce: 0.4), value: selected)
        }
        .buttonStyle(PressScaleStyle())
    }
}

/// The light that sweeps across "Paling hemat" every 2.6 s, starting 0.9 s in (the design's "shine").
private struct Shine: View {
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start) - 0.9
            let phase = elapsed < 0 ? 1.0 : elapsed.truncatingRemainder(dividingBy: 2.6) / 2.6
            // 0-55% of the cycle moves the light from the right to the left edge; the rest it rests off the pill
            let position = 160 - 280 * min(phase / 0.55, 1)
            GeometryReader { proxy in
                LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .white.opacity(0.6), location: 0.5),
                                       .init(color: .clear, location: 0.65)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width * 2.5)
                    .offset(x: (proxy.size.width - proxy.size.width * 2.5) * position / 100)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Motion helpers

/// CSS-like motion: every animation in the design is a function of the seconds since its scene began.
private enum Mo {
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    /// Ease-out close to cubic-bezier(.2,.9,.25,1).
    static func ease(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3.2) }
    /// An animation of `dur` ms that starts after `delay` ms, held before and after ("both").
    static func p(_ t: Double, _ delay: Double, _ dur: Double) -> Double { ease((t * 1000 - delay) / dur) }
    /// Keyframes over the scene's 4.8 s: stops are (percent, value), linear in between.
    static func kf(_ t: Double, _ stops: [(Double, Double)]) -> Double {
        let f = t / 4.8 * 100
        guard let first = stops.first, let last = stops.last else { return 0 }
        if f <= first.0 { return first.1 }
        if f >= last.0 { return last.1 }
        for i in 1..<stops.count where f <= stops[i].0 {
            let a = stops[i - 1], b = stops[i]
            return a.1 + (b.1 - a.1) * (f - a.0) / (b.0 - a.0)
        }
        return last.1
    }

    struct Fx { var o = 1.0, x = 0.0, y = 0.0, s = 1.0, r = 0.0 }

    static func s1(_ t: Double) -> Fx { Fx(o: kf(t, [(0, 0), (6, 1), (30, 1), (38, 0)]), y: kf(t, [(0, -20), (6, 0), (30, 0), (38, -6)]), s: kf(t, [(0, 1), (30, 1), (38, 0.9)])) }
    static func s2(_ t: Double) -> Fx { Fx(o: kf(t, [(0, 0), (30, 0), (36, 1), (44, 1), (50, 0)]), y: kf(t, [(0, 8), (30, 8), (36, 0)]), s: kf(t, [(0, 1), (44, 1), (50, 0.9)])) }
    static func s3(_ t: Double) -> Fx { Fx(o: kf(t, [(0, 0), (46, 0), (54, 1), (94, 1), (100, 0)]), y: kf(t, [(0, 14), (46, 14), (54, 0)])) }
    static func out(_ t: Double) -> Double { kf(t, [(0, 1), (40, 1), (48, 0)]) }
    static func inn(_ t: Double) -> Fx { Fx(o: kf(t, [(0, 0), (44, 0), (54, 1)]), y: kf(t, [(0, 6), (44, 6), (54, 0)])) }
    static func btnOut(_ t: Double) -> Double { kf(t, [(0, 1), (70, 1), (74, 0)]) }
    static func btnIn(_ t: Double) -> Fx { Fx(o: kf(t, [(0, 0), (72, 0), (78, 1)]), s: kf(t, [(0, 0.7), (72, 0.7), (78, 1)])) }
    /// Fade up from 14 pt.
    static func hin(_ t: Double, _ delay: Double, _ dur: Double) -> Fx { let u = p(t, delay, dur); return Fx(o: u, y: 14 * (1 - u)) }
    static func slideL(_ t: Double, _ delay: Double, _ dur: Double) -> Fx { let u = p(t, delay, dur); return Fx(o: u, x: -30 * (1 - u)) }
    /// Scale 0 to 1.15 and settle at 1.
    static func pop(_ t: Double, _ delay: Double, _ dur: Double) -> Fx {
        let u = clamp((t * 1000 - delay) / dur)
        return Fx(o: min(1, u / 0.6), s: u < 0.6 ? 1.15 * u / 0.6 : 1.15 - 0.15 * (u - 0.6) / 0.4)
    }
}

private extension View {
    func fx(_ f: Mo.Fx) -> some View {
        opacity(f.o).scaleEffect(f.s).rotationEffect(.degrees(f.r)).offset(x: f.x, y: f.y)
    }
}

private extension Color {
    /// The paywall's own surface (the design's "surface-dialog"): white, or #1C1C1E in dark.
    static let paywallSurface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
}

/// The paywall's story: eight short scenes that replace a feature list, each with its own choreography (a
/// notification becomes a draft, a receipt is scanned, the free limit lifts, ...). Swipe or tap a dot to move; it
/// also advances by itself every 4.8 s.
private struct PaywallHero: View {
    let compact: Bool

    private static let sceneCount = 8
    private static let duration = 4.8

    @State private var index = 0
    @State private var start = Date()
    /// Changes when the user moves the hero, so the 4.8 s timer starts over.
    @State private var restart = 0

    private var height: CGFloat { compact ? 116 : 200 }
    private var scale: CGFloat { compact ? 0.62 : 1.1 }

    private var captions: [String] { [
        L("Notifikasi bank jadi draf, tinggal simpan"), L("Foto struk dibaca otomatis"), L("Teruskan email, draf siap disimpan"),
        L("Dompet, kategori, budget tanpa batas"), L("Bantuan AI tanpa batas"), L("Laporan PDF bulanan"),
        L("Data tetap milikmu"), L("Batalkan kapan saja"),
    ] }

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation) { context in
                let t = min(context.date.timeIntervalSince(start), Self.duration)
                GeometryReader { proxy in
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color.stChip)
                        sceneView(t)
                            .frame(width: 300, height: 110)
                            .scaleEffect(scale)
                            .position(x: proxy.size.width / 2, y: (height - 40) / 2)
                        Text(captions[index]).font(.app(13, weight: .semibold)).foregroundStyle(Color.appText)
                            .fx(Mo.hin(t, 200, 400))
                            .position(x: proxy.size.width / 2, y: height - 22 - 8)
                    }
                    .opacity(Mo.clamp(t / 0.26))
                }
                .frame(height: height)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.width < -30 { go(index + 1) } else if value.translation.width > 30 { go(index - 1) }
            })
            dots
        }
        .task(id: restart) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.duration))
                if Task.isCancelled { return }
                index = (index + 1) % Self.sceneCount
                start = Date()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captions[index])
    }

    private var dots: some View {
        TimelineView(.animation) { context in
            let progress = Mo.clamp(context.date.timeIntervalSince(start) / Self.duration)
            HStack(spacing: 4) {
                ForEach(0..<Self.sceneCount, id: \.self) { i in
                    Button { go(i) } label: {
                        ZStack(alignment: .leading) {
                            Capsule().fill(i < index ? Color.appPrimary : Color.appBorder.opacity(0.6))
                            if i == index { Capsule().fill(Color.appPrimary).scaleEffect(x: progress, anchor: .leading) }
                        }
                        .frame(width: 14, height: 3).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func go(_ target: Int) {
        index = (target + Self.sceneCount) % Self.sceneCount
        start = Date()
        restart += 1
    }

    // MARK: Scenes (a 300 x 110 canvas)

    @ViewBuilder private func sceneView(_ t: Double) -> some View {
        switch index {
        case 0: notificationToDraft(t, badge: AnyView(brandBadge("BCA", Color(light: 0x0060AF, dark: 0x0060AF))),
                                    title: "BCA mobile", body: "Debit Rp45.000 · KOPI KENANGAN", trailing: L("sekarang"),
                                    pillIcon: "bolt.fill", pill: L("Saku membuat draf"),
                                    icon: "cup.and.saucer", name: "Kopi Kenangan", sub: L("Draf · Makan · dari notifikasi BCA"), amount: "−Rp45.000")
        case 1: receipt(t)
        case 2: notificationToDraft(t, badge: AnyView(symbolBadge("envelope", Color(light: 0x6E6E73, dark: 0x636366))),
                                    title: "Tokopedia", body: "Pesanan selesai · Rp249.000", trailing: "Email",
                                    pillIcon: "arrowshape.turn.up.right.fill", pill: L("Diteruskan ke catat@saku.id"),
                                    icon: "shippingbox", name: "Tokopedia", sub: L("Draf · Belanja · dari email"), amount: "−Rp249.000")
        case 3: freeLimit(t)
        case 4: aiChat(t)
        case 5: pdfReport(t)
        case 6: dataStays(t)
        default: cancelSwitch(t)
        }
    }

    private func brandBadge(_ text: String, _ color: Color) -> some View {
        Text(verbatim: text).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(color, in: RoundedRectangle(cornerRadius: 7))
    }

    private func symbolBadge(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 15)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(color, in: RoundedRectangle(cornerRadius: 7))
    }

    private func card<Content: View>(radius: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        content().background(Color.paywallSurface, in: RoundedRectangle(cornerRadius: radius))
            .shadow(color: .black.opacity(0.08), radius: 7, y: 4)
    }

    /// Scenes 1 and 3: it arrives, Saku turns it into a draft, the draft is saved.
    private func notificationToDraft(_ t: Double, badge: AnyView, title: String, body: String, trailing: String,
                                     pillIcon: String, pill: String, icon: String, name: String, sub: String, amount: String) -> some View {
        ZStack(alignment: .topLeading) {
            card {
                HStack(spacing: 10) {
                    badge
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: title).font(.app(12, weight: .semibold)).foregroundStyle(Color.appText)
                        Text(verbatim: body).font(.app(12)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(verbatim: trailing).font(.app(11)).foregroundStyle(Color.appTextTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(width: 300).fx(Mo.s1(t)).offset(y: 20)

            HStack(spacing: 8) {
                Image(systemName: pillIcon).font(.system(size: 12, weight: .bold))
                Text(verbatim: pill).font(.app(12, weight: .semibold))
            }
            .foregroundStyle(Color.paywallSurface).padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.appText, in: Capsule())
            .frame(width: 300).fx(Mo.s2(t)).offset(y: 38)

            card(radius: 16) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.appTextSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: name).font(.app(14)).foregroundStyle(Color.appText)
                            Text(verbatim: sub).font(.app(11)).foregroundStyle(Color.appTextSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: amount).font(.app(14)).monospacedDigit().foregroundStyle(Color.appText)
                    }
                    ZStack {
                        Text("Simpan").font(.app(13, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.appPrimary, in: Capsule())
                            .opacity(Mo.btnOut(t))
                        Label(L("Tersimpan"), systemImage: "checkmark").font(.app(13, weight: .semibold)).foregroundStyle(Color.appPrimary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.appPrimary.opacity(0.12), in: Capsule())
                            .fx(Mo.btnIn(t))
                    }
                    .frame(height: 30)
                }
                .padding(12)
            }
            .frame(width: 300).fx(Mo.s3(t)).offset(y: 4)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    /// Scene 2: the receipt is scanned, then store, amount and date slide in.
    private func receipt(_ t: Double) -> some View {
        let scanU = Mo.clamp((t * 1000 - 500) / 1400)
        let scanTop = (scanU < 0.5 ? scanU * 2 : 2 - scanU * 2) * 108
        return ZStack(alignment: .topLeading) {
            card(radius: 4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "INDOMARET").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.appText)
                    Rectangle().fill(Color.appFill).frame(width: 80 * 0.8, height: 3)
                    Rectangle().fill(Color.appFill).frame(width: 60 * 0.8, height: 3)
                    Rectangle().fill(Color.appFill).frame(width: 70 * 0.8, height: 3)
                    Spacer(minLength: 0)
                    Text(verbatim: "87.500").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appText)
                }
                .padding(.horizontal, 10).padding(.vertical, 12).frame(width: 104, height: 110, alignment: .topLeading)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.appPrimary).frame(height: 2).shadow(color: Color.appPrimary, radius: 5)
                        .offset(y: scanTop).opacity(scanU >= 1 ? 0 : 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .rotationEffect(.degrees(-4)).fx(Mo.hin(t, 0, 500)).offset(x: 8)

            VStack(alignment: .leading, spacing: 8) {
                chip("storefront", "Indomaret", t, 1500)
                chip("bitcoinsign.circle", "−Rp87.500", t, 1720)
                chip("calendar", "16 Okt", t, 1940)
            }
            .offset(x: 136, y: 8)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    private func chip(_ icon: String, _ text: String, _ t: Double, _ delay: Double) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.appTextSecondary)
            Text(verbatim: text).font(.app(13)).foregroundStyle(Color.appText)
        }
        .padding(.horizontal, 10).frame(height: 26).background(Color.paywallSurface, in: Capsule())
        .fx(Mo.slideL(t, delay, 420))
    }

    /// Scene 4: five wallets fill the limit, then it lifts: "5/5" turns to infinity and 19 more bars grow.
    private func freeLimit(_ t: Double) -> some View {
        let out = Mo.out(t), inn = Mo.inn(t)
        let capScale = Mo.kf(t, [(0, 1), (30, 1), (40, 0)]), capOpacity = Mo.kf(t, [(0, 1), (30, 1), (40, 0)])
        return ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom) {
                Text("Dompet").font(.app(13)).foregroundStyle(Color.appTextSecondary)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    ZStack(alignment: .trailing) {
                        Text("5").opacity(out)
                        Text("24").fx(inn)
                    }
                    .frame(width: 44, height: 34, alignment: .trailing).clipped()
                    ZStack(alignment: .bottomLeading) {
                        Text("/5").font(.app(18)).foregroundStyle(Color.appTextTertiary).opacity(out)
                        Image(systemName: "infinity").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.appPrimary).fx(inn)
                    }
                    .frame(width: 34, height: 34, alignment: .bottomLeading)
                }
                .font(.app(34, weight: .ultraLight)).tracking(-1).monospacedDigit().foregroundStyle(Color.appText)
            }
            .frame(width: 300).offset(y: 6)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let delay = i < 5 ? Double(i) * 60 : 1500 + Double(i - 5) * 45
                    Rectangle().fill(Color.appPrimary).frame(height: 26)
                        .scaleEffect(y: Mo.p(t, delay, 220), anchor: .bottom)
                }
            }
            .frame(width: 300, height: 26).offset(y: 58)

            Rectangle().fill(Color.appError).frame(width: 2, height: 40)
                .scaleEffect(y: capScale, anchor: .bottom).opacity(capOpacity)
                .offset(x: 5 * (300 + 3) / 24 - 3, y: 50)
            Text("Batas gratis").font(.app(11, weight: .semibold)).foregroundStyle(Color.appError).opacity(out)
                .offset(x: 5 * (300 + 3) / 24 + 4, y: 92)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    /// Scene 5: a sentence is read into two transactions.
    private func aiChat(_ t: Double) -> some View {
        let sweep = Mo.clamp((t * 1000 - 700) / 1800)
        let sweepX = (sweep * 2).truncatingRemainder(dividingBy: 1) * 2 - 1
        return ZStack(alignment: .topLeading) {
            Text(verbatim: "tadi grab 25rb terus makan 40rb").font(.app(14)).foregroundStyle(Color.appText)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.paywallSurface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, Color.appPrimary.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                            .offset(x: sweepX * proxy.size.width).opacity(sweep > 0 && sweep < 1 ? 1 : 0)
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
                }
                .frame(width: 300, alignment: .trailing).fx(Mo.hin(t, 0, 420))
            Label(L("Terbaca 2 transaksi"), systemImage: "sparkles").font(.app(11, weight: .semibold)).foregroundStyle(Color.appPrimary)
                .fx(Mo.hin(t, 2400, 300)).offset(y: 50)
            VStack(spacing: 0) {
                row("car", "Grab", "−Rp25.000").fx(Mo.slideL(t, 2500, 380))
                row("fork.knife", L("Makan"), "−Rp40.000").fx(Mo.slideL(t, 2680, 380))
            }
            .frame(width: 300).offset(y: 68)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    private func row(_ icon: String, _ name: String, _ amount: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Color.appTextSecondary).frame(width: 20)
            Text(verbatim: name).font(.app(14)).foregroundStyle(Color.appText)
            Spacer(minLength: 0)
            Text(verbatim: amount).font(.app(14)).monospacedDigit().foregroundStyle(Color.appText)
        }
        .frame(height: 22)
    }

    /// Scene 6: the month's bars grow, then a report page slides in and is stamped PDF.
    private func pdfReport(_ t: Double) -> some View {
        let heights: [CGFloat] = [40, 62, 48, 80, 56, 70]
        let pageU = Mo.p(t, 1300, 600)
        return ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2).fill(i == 3 ? Color.appPrimary : Color.appBorder)
                        .frame(width: 14, height: heights[i]).scaleEffect(y: Mo.p(t, Double(i) * 90, 500), anchor: .bottom)
                }
            }
            .frame(height: 84, alignment: .bottom).offset(x: 12, y: 110 - 6 - 84)

            card(radius: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Okt 2026").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.appText)
                    Rectangle().fill(Color.appFill).frame(width: 96 * 0.8 - 8, height: 3)
                    Rectangle().fill(Color.appFill).frame(width: 96 * 0.6 - 6, height: 3)
                    RoundedRectangle(cornerRadius: 2).fill(Color.appPrimary.opacity(0.12)).frame(height: 22).padding(.top, 4)
                    Spacer(minLength: 0)
                    Text(verbatim: "PDF").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color(light: 0x111111, dark: 0x3A3A3C), in: RoundedRectangle(cornerRadius: 4))
                        .fx(Mo.pop(t, 2100, 380))
                }
                .padding(.horizontal, 10).padding(.vertical, 12).frame(width: 96, height: 112, alignment: .topLeading)
            }
            .fx(Mo.Fx(o: pageU, x: 40 * (1 - pageU), y: 10 * (1 - pageU), r: 3 + 5 * (1 - pageU)))
            .offset(x: 300 - 14 - 96)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    /// Scene 7: Plus ends, and every transaction (1.284 of them) is still there.
    private func dataStays(_ t: Double) -> some View {
        let out = Mo.out(t), inn = Mo.inn(t)
        return ZStack(alignment: .topLeading) {
            HStack {
                ZStack(alignment: .leading) {
                    Text("Saku Plus").font(.app(12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 24).background(Color.appPrimary, in: Capsule()).opacity(out)
                    Text("Saku Gratis").font(.app(12, weight: .semibold)).foregroundStyle(Color.appText)
                        .padding(.horizontal, 10).frame(height: 24).background(Color.paywallSurface, in: Capsule()).fx(inn)
                }
                Spacer()
                Text("1.284 transaksi").font(.app(12)).foregroundStyle(Color.appTextSecondary)
            }
            .frame(width: 300)
            VStack(spacing: 2) {
                checkRow("cup.and.saucer", "Kopi Kenangan", "−Rp45.000", Color.appText, t, 2700)
                checkRow("cart", "Indomaret", "−Rp87.500", Color.appText, t, 2850)
                checkRow("arrow.down.left", L("Gaji Oktober"), "+Rp12.000.000", Color.appPrimary, t, 3000)
            }
            .frame(width: 300).offset(y: 34)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }

    private func checkRow(_ icon: String, _ name: String, _ amount: String, _ amountColor: Color, _ t: Double, _ delay: Double) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Color.appTextSecondary).frame(width: 20)
            Text(verbatim: name).font(.app(14)).foregroundStyle(Color.appText)
            Spacer(minLength: 0)
            Text(verbatim: amount).font(.app(14)).monospacedDigit().foregroundStyle(amountColor)
            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color.appPrimary).fx(Mo.pop(t, delay, 380))
        }
        .frame(height: 24)
    }

    /// Scene 8: the subscription is switched off in two taps and nothing is lost.
    private func cancelSwitch(_ t: Double) -> some View {
        let out = Mo.out(t), inn = Mo.inn(t)
        let off = Mo.kf(t, [(0, 0), (40, 0), (52, 1)])
        return ZStack(alignment: .topLeading) {
            card {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saku Plus · Tahunan").font(.app(15)).foregroundStyle(Color.appText)
                        ZStack(alignment: .leading) {
                            Text("Diperpanjang 15 Okt").font(.app(12)).foregroundStyle(Color.appTextSecondary).opacity(out)
                            Text("Dibatalkan · tanpa biaya").font(.app(12)).foregroundStyle(Color.appText).fx(inn)
                        }
                        .frame(height: 16, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.appPrimary.opacity(1 - off).blended(with: Color(light: 0xD2D2D7, dark: 0x48484A), amount: off))
                        Circle().fill(.white).frame(width: 24, height: 24).shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                            .offset(x: 2 + 18 * (1 - off))
                    }
                    .frame(width: 46, height: 28)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .frame(width: 300).offset(y: 4)
            Text("Datamu tetap ada setelahnya").font(.app(12)).foregroundStyle(Color.appTextSecondary)
                .frame(width: 300).fx(Mo.hin(t, 2600, 400)).offset(y: 76)
        }
        .frame(width: 300, height: 110, alignment: .topLeading)
    }
}

private extension Color {
    /// A simple cross-fade between two colors (the switch track turning grey).
    func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self).resolvedColor(with: .current), b = UIColor(other).resolvedColor(with: .current)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0, br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let u = CGFloat(amount)
        return Color(red: ar + (br - ar) * u, green: ag + (bg - ag) * u, blue: ab + (bb - ab) * u)
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
