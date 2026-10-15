import SwiftUI

/// Three swipeable slides built from real app parts (card stack, segment bars,
/// health score). Each slide replays its animation when it becomes current.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var slide = 0
    @State private var isPlaying = false
    /// 0→1 ease-out driving the counters on the current slide.
    @State private var progress = 0.0
    @State private var dragX: CGFloat = 0
    @State private var playTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Lewati") { go(2) }
                        .font(.app(17))
                        .foregroundStyle(Color.appTextSecondary)
                        .opacity(slide < 2 ? 1 : 0)
                        .animation(.easeInOut(duration: 0.3), value: slide)
                        .disabled(slide == 2)
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                HStack(spacing: 0) {
                    walletsSlide.frame(width: w)
                    budgetSlide.frame(width: w)
                    healthSlide.frame(width: w)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(slide) * w + dragX)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
                .gesture(swipe)

                footer
            }
        }
        .background(Color.appBackground)
        .onAppear { play() }
        .onDisappear { playTask?.cancel() }
    }

    // MARK: - Paging

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                var dx = value.translation.width
                if (slide == 0 && dx > 0) || (slide == 2 && dx < 0) { dx *= 0.3 }
                dragX = dx
            }
            .onEnded { _ in
                let dx = dragX
                withAnimation(.settle(0.68)) { dragX = 0 }
                if dx < -50 { go(slide + 1) } else if dx > 50 { go(slide - 1) }
            }
    }

    private func go(_ index: Int) {
        let index = min(max(index, 0), 2)
        guard index != slide else { return }
        withAnimation(.settle(0.68)) { slide = index }
        play()
    }

    private func play() {
        playTask?.cancel()
        isPlaying = false
        progress = 0
        playTask = Task {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            isPlaying = true
            withAnimation(.timingCurve(0.33, 1, 0.68, 1, duration: 1.4).delay(0.3)) { progress = 1 }
        }
    }

    private func isVisible(_ index: Int) -> Bool { isPlaying && slide == index }

    // MARK: - Slides

    private static let heroCards: [(name: String, color: String, amount: String, kind: String, angle: Double)] = [
        ("BCA", "0066AE", "Rp15.200.000", "Bank · Utama", -9),
        ("GOPAY", "00AA44", "Rp1.450.000", "E-Wallet", 7),
        ("VISA", "1A1F71", "Rp7.520.000", "Kartu kredit", -4),
    ]

    private var walletsSlide: some View {
        let on = isVisible(0)
        return slidePage(title: L("Semua dompet dalam satu kantong."),
                         subtitle: L("Bank, e-wallet, tunai, dan kartu kredit. Semua saldo dalam satu layar."),
                         isShown: on) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total saldo · 3 akun")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                    HStack(alignment: .top, spacing: 3) {
                        Text("Rp")
                            .font(.app(17))
                            .foregroundStyle(Color.appTextSecondary)
                            .padding(.top, 5)
                        CountingText(value: 24_350_000 * (slide == 0 ? progress : 0)) { $0.formattedAsDigits() }
                            .font(.app(40, weight: .light))
                            .tracking(-1.4)
                    }
                    .monospacedDigit()
                }
                .padding(.top, 16)
                .opacity(on ? 1 : 0)
                .animation(.easeInOut(duration: 0.5).delay(0.5), value: on)

                ForEach(Self.heroCards.indices, id: \.self) { k in
                    let c = Self.heroCards[k]
                    let delay = Double(k) * 0.13
                    heroCard(c.name, color: c.color, amount: c.amount, kind: c.kind)
                        .opacity(on ? 1 : 0)
                        .animation(.easeInOut(duration: 0.4).delay(delay), value: on)
                        .rotationEffect(.degrees(on ? 0 : c.angle))
                        .offset(y: on ? 0 : 280 + CGFloat(k) * 40)
                        .animation(.settle(0.9).delay(delay), value: on)
                        .offset(y: 100 + CGFloat(k) * 56)
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func heroCard(_ name: String, color: String, amount: String, kind: String) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(hex: color))
            .overlay(alignment: .topTrailing) {
                ZStack(alignment: .topTrailing) {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                        .frame(width: 220, height: 220)
                        .offset(x: 50, y: -70)
                    Circle().fill(.white.opacity(0.06))
                        .frame(width: 150, height: 150)
                        .offset(x: 20, y: -40)
                }
            }
            .overlay(alignment: .top) {
                HStack {
                    Text(name).font(.app(15, weight: .heavy)).tracking(0.6)
                    Spacer()
                    Text(amount).font(.app(15, weight: .semibold)).monospacedDigit()
                }
                .frame(height: 56)
                .padding(.horizontal, 18)
            }
            .overlay(alignment: .bottomLeading) {
                Text(L(kind))
                    .font(.app(12))
                    .opacity(0.82)
                    .padding(.leading, 18)
                    .padding(.bottom, 16)
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(height: 196)
            .shadow(color: .black.opacity(0.16), radius: 7, y: -3)
    }

    private static let budgets: [(name: String, icon: String, ratio: Double, color: Color, label: String, labelColor: Color)] = [
        ("Transportasi", "car", 0.48, .appPrimary, "Sisa Rp420.000", .appTextSecondary),
        ("Makan Harian", "fork.knife", 0.8, .appWarning, "Rp75.000/hari", .appWarning),
        ("Jajan & Kopi", "cup.and.saucer", 1, .appError, "Lewat Rp20.000", .appError),
    ]

    private var budgetSlide: some View {
        let on = isVisible(1)
        return slidePage(title: L("Sisa budget terlihat jelas."),
                         subtitle: L("Hijau aman, oranye hampir habis, merah lewat batas."),
                         isShown: on) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L("Budget"), trailing: L("September"))
                    .padding(.bottom, 8)
                    .opacity(on ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: on)

                ForEach(Self.budgets.indices, id: \.self) { j in
                    let b = Self.budgets[j]
                    HStack(spacing: 14) {
                        Image(systemName: b.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 24)
                        VStack(spacing: 10) {
                            HStack {
                                Text(L(b.name)).font(.app(16, weight: .medium))
                                Spacer()
                                Text(L(b.label)).font(.app(14)).foregroundStyle(b.labelColor)
                            }
                            SegmentTrack(count: 30, filled: on ? Int((b.ratio * 30).rounded()) : 0, color: b.color,
                                         delay: 0.35 + Double(j) * 0.17, step: 0.016)
                                .frame(height: 10)
                        }
                    }
                    .padding(.vertical, 20)
                    .rowSeparator()
                    .rise(on, y: 28, delay: Double(j) * 0.14, fade: 0.4)
                }
            }
            .foregroundStyle(Color.appText)
            .padding(.top, 40)
            .padding(.horizontal, 32)
        }
    }

    private var healthSlide: some View {
        let on = isVisible(2)
        let q = slide == 2 ? progress : 0
        return slidePage(title: L("Satu angka untuk kondisi keuanganmu."),
                         subtitle: L("Dari arus kas, budget, dana darurat, dan kebiasaan mencatat. Diperbarui tiap kamu mencatat."),
                         isShown: on) {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: L("Kesehatan finansial"), trailing: L("Baik"), trailingColor: .appPrimary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    CountingText(value: 78 * q) { String(Int($0.rounded())) }
                        .font(.app(88, weight: .light))
                        .tracking(-4)
                    Text("/ 100")
                        .font(.app(22))
                        .foregroundStyle(Color.appTextSecondary)
                }
                .padding(.top, 18)

                SegmentTrack(count: 40, filled: on ? 31 : 0, gap: 3, delay: 0.25, step: 0.026, duration: 0.22)
                    .frame(height: 26)
                    .padding(.top, 22)

                HStack(spacing: 0) {
                    stat(L("Arus kas"), 32 * q, of: 40)
                    stat(L("Budget"), 26 * q, of: 35)
                    stat(L("Dana darurat"), 20 * q, of: 25)
                }
                .padding(.top, 22)
            }
            .monospacedDigit()
            .foregroundStyle(Color.appText)
            .opacity(on ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: on)
            .padding(.top, 70)
            .padding(.horizontal, 32)
        }
    }

    private func stat(_ label: String, _ value: Double, of max: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            HStack(spacing: 0) {
                CountingText(value: value) { String(Int($0.rounded())) }
                Text("/\(max)").foregroundStyle(Color.appTextTertiary)
            }
            .font(.app(17))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Visual area on top (432pt), title and subtitle rising in below it.
    private func slidePage(title: String, subtitle: String, isShown: Bool, @ViewBuilder visual: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            visual()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 432, alignment: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.app(34, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(Color.appText)
                    .rise(isShown, delay: 0.25)
                Text(subtitle)
                    .font(.app(17))
                    .lineSpacing(2.6)
                    .foregroundStyle(Color.appTextSecondary)
                    .rise(isShown, delay: 0.35)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == slide ? Color.appText : Color.appBorder)
                        .frame(width: i == slide ? 24 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -8))
                        .onTapGesture { go(i) }
                }
            }
            .animation(.settle(0.42), value: slide)
            .accessibilityElement()
            .accessibilityLabel(L("Halaman %lld dari 3", slide + 1))

            PrimaryButton(title: slide < 2 ? L("Lanjut") : L("Mulai"), trailingIcon: "arrow.right") {
                if slide < 2 { go(slide + 1) } else { onFinish() }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }
}

#Preview {
    OnboardingView {}
}
