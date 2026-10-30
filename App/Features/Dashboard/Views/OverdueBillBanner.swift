import SwiftUI

/// Beranda's "Sudah kamu bayar?" for card bills past their due date (Pengingat Tagihan 1c): one
/// card per overdue bill, stacked when there are several (design "Credit Card Swipe"). Drag the front card away and
/// the next one rises from behind. "Sembunyikan" folds the open bills into a one-line
/// reminder until tomorrow morning; "Buka dompet" opens the card's detail, where the bill is marked as paid, and once
/// it is paid the card shows "Tagihan dicatat" and lifts away.
struct OverdueBillBanner: View {
    let bills: [OverdueCardBill]
    let isBalanceVisible: Bool
    let onOpenWallet: (OverdueCardBill) -> Void

    @State private var order: [String] = []
    @State private var later: Set<String> = []
    @State private var dx: CGFloat = 0
    @State private var isDragging = false
    @State private var isFlying = false
    /// Set for a moment while the stack is reordered, so the cards land in place without moving (as in the design).
    @State private var still = false
    /// The bill that was just paid, kept on screen for its "Tagihan dicatat" moment.
    @State private var departing: OverdueCardBill?
    @State private var departStage = 0
    @State private var lastBills: [OverdueCardBill] = []

    private let store = BillReminderStore()
    private let cardHeight: CGFloat = 232
    /// The design's curve for everything that moves: fast, then settling, 280 ms.
    private let curve = Animation.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.28)

    private var open: [OverdueCardBill] {
        order.compactMap { id in bills.first { $0.id == id && !later.contains(id) } }
    }
    private var laterBills: [OverdueCardBill] { bills.filter { later.contains($0.id) } }

    var body: some View {
        VStack(spacing: 14) {
            if !open.isEmpty || departing != nil { stack }
            if !laterBills.isEmpty { laterRow }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .onAppear(perform: sync)
        .onChange(of: bills.map(\.id)) { _, _ in sync() }
    }

    /// Follows the bills as they load or get paid, and re-reads which ones are snoozed.
    private func sync() {
        let ids = bills.map(\.id)
        // a bill that left without being snoozed was paid: show "Tagihan dicatat" on its card
        if departing == nil, let paid = lastBills.first(where: { !ids.contains($0.id) && !later.contains($0.id) }) {
            playRecorded(paid)
        }
        lastBills = bills
        order = order.filter(ids.contains) + ids.filter { !order.contains($0) }
        later = Set(bills.filter { store.isSnoozed(card: $0.card.id, statementDate: $0.statement.statementDate) }.map(\.id))
    }

    private func playRecorded(_ bill: OverdueCardBill) {
        // the card stays as it was while the sheet closes, then turns into the check, then lifts away
        departing = bill
        departStage = 0
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            departStage = 1
            try? await Task.sleep(for: .seconds(0.95))
            withAnimation(.settle(0.4)) { departStage = 2 }
            try? await Task.sleep(for: .seconds(0.45))
            withAnimation(.settle(0.42)) { departing = nil }
            departStage = 0
        }
    }

    // MARK: Stack

    private var stack: some View {
        let cards = open
        let lead = departing != nil && departStage < 2 ? 1 : 0
        let count = cards.count + (departing != nil ? 1 : 0)
        return VStack(spacing: 14) {
            ZStack(alignment: .top) {
                ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { position, bill in
                    card(bill, position: position + lead, count: count, recorded: false)
                }
                if let departing {
                    card(departing, position: 0, count: count, recorded: true)
                }
            }
            .frame(height: cardHeight + (count > 2 ? 28 : count > 1 ? 14 : 0), alignment: .top)
            .animation(.settle(0.3), value: count)
            if bills.count > 1 { dots(cards) }
            if !cards.isEmpty {
                Button(action: hideAll) {
                    Text(cards.count > 1 ? L("Sembunyikan semua") : L("Sembunyikan"))
                        .font(.app(14, weight: .medium))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(height: 32)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    /// Folds every open bill into the one-line reminder until tomorrow morning.
    private func hideAll() {
        guard departing == nil else { return }
        for bill in open { snooze(bill) }
    }

    /// Where a card sits in the stack: the ones behind rise toward the front as the front card is dragged away.
    private var progress: CGFloat { min(abs(dx) / 120, 1) }

    private func card(_ bill: OverdueCardBill, position: Int, count: Int, recorded: Bool) -> some View {
        let isFront = position == 0
        let behind = CGFloat(min(position, 2)) - (isFront ? 0 : progress)
        let color = bill.card.walletColor
        let universe = departing != nil ? lastBills : bills
        let index = (universe.firstIndex { $0.id == bill.id } ?? 0) + 1
        let canSwipe = isFront && !recorded && count > 1 && departing == nil
        let lifted = recorded && departStage >= 2
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                logoChip(bill.card, color: color)
                Text(count > 1 ? L("%@ sudah lewat", bill.card.name) : L("Tagihan %@ sudah lewat", bill.card.name))
                    .font(.app(17, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if universe.count > 1 {
                    Text("\(index)/\(universe.count)")
                        .font(.app(13, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(.white.opacity(0.2), in: Capsule())
                }
            }
            Text(isBalanceVisible ? bill.statement.remaining.formattedAsCurrency() : "Rp" + hiddenAmount)
                .font(.app(44, weight: .ultraLight))
                .tracking(-1)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 2)
            Text("Jatuh tempo \(TransactionDates.dayMonth.string(from: bill.statement.dueDate)). Sudah kamu bayar?")
                .font(.app(14))
                .foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            Button { onOpenWallet(bill) } label: {
                Text("Buka dompet")
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(!isFront || recorded)
        }
        .foregroundStyle(.white)
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(color)
                .overlay(
                    LinearGradient(stops: [.init(color: .white.opacity(0.2), location: 0), .init(color: .white.opacity(0), location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 12)
        }
        .overlay { if recorded { recordedOverlay(color: color) } }
        .scaleEffect(lifted ? 0.96 : 1 - behind * 0.07, anchor: .bottom)
        .offset(y: lifted ? -18 : behind * 14)
        .offset(x: isFront && !recorded && count > 1 ? dx : 0)
        .opacity(lifted ? 0 : 1 - (isFront && !recorded ? Double(min(abs(dx) / 460, 1)) * 0.7 : 0))
        .zIndex(Double(10 - position))
        .gesture(canSwipe ? swipe : nil)
        .animation(still ? nil : curve, value: position)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(bill.card.name), tagihan \(bill.statement.remaining.formattedAsCurrency()) lewat jatuh tempo")
    }

    /// "Tagihan dicatat": the card turns into a plain check on its own colour.
    private func recordedOverlay(color: Color) -> some View {
        let on = departStage >= 1
        return VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 60, height: 60)
                .background(.white, in: Circle())
                .scaleEffect(on ? 1 : 0.4)
                .animation(.spring(duration: 0.42, bounce: 0.5), value: on)
            Text("Tagihan dicatat")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(on ? 1 : 0)
                .offset(y: on ? 0 : 8)
                .animation(.settle(0.3).delay(0.12), value: on)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(color, in: RoundedRectangle(cornerRadius: 28))
        .opacity(on ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: on)
    }

    private func logoChip(_ card: Account, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white)
            .frame(width: 44, height: 34)
            .overlay {
                if let logo = card.brandLogo {
                    Image(logo).resizable().scaledToFit().frame(width: 30, height: 16)
                } else {
                    Image(systemName: card.typeSymbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(color)
                }
            }
    }

    /// Fling the front card away to bring the next bill up; a short drag springs back.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard !isFlying else { return }
                isDragging = true
                dx = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                guard !isFlying else { return }
                guard abs(value.translation.width) > 80 else {
                    withAnimation(curve) { dx = 0 }
                    return
                }
                let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                isFlying = true
                withAnimation(curve) { dx = direction * 460 }
                Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    // the flown card goes to the back and the rest are already where they will be: nothing moves
                    var reset = SwiftUI.Transaction()
                    reset.disablesAnimations = true
                    still = true
                    withTransaction(reset) {
                        if let first = order.first(where: { id in open.contains { $0.id == id } }) {
                            order.removeAll { $0 == first }
                            order.append(first)
                        }
                        dx = 0
                    }
                    isFlying = false
                    try? await Task.sleep(for: .milliseconds(40))
                    still = false
                }
            }
    }

    private func dots(_ cards: [OverdueCardBill]) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(bills) { bill in
                    let isFront = cards.first?.id == bill.id
                    Capsule()
                        .fill(isFront ? Color.appText : Color.appBorder)
                        .frame(width: isFront ? 22 : 8, height: 8)
                        .contentShape(Rectangle().inset(by: -8))
                        .onTapGesture {
                            guard !later.contains(bill.id) else { return }
                            withAnimation(.settle(0.42)) {
                                order.removeAll { $0 == bill.id }
                                order.insert(bill.id, at: 0)
                            }
                        }
                        .accessibilityLabel(bill.card.name)
                }
            }
            Text("Geser untuk lihat tagihan lain")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
        }
        .animation(.settle(0.3), value: cards.first?.id)
    }

    // MARK: Snoozed

    private var laterRow: some View {
        let first = laterBills[0]
        let text = laterBills.count > 1 ? L("%lld tagihan belum dibayar · ingatkan besok", laterBills.count) : L("Belum dibayar · ingatkan besok")
        return Button {
            withAnimation(.settle(0.42)) {
                for bill in laterBills {
                    store.clear(card: bill.card.id, statementDate: bill.statement.statementDate)
                }
                later = []
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(first.card.walletColor)
                    .frame(width: 26, height: 17)
                Text(text)
                    .font(.app(14))
                    .foregroundStyle(Color.appBody)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .frame(height: 44)
            .background(Color.appFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint("Tampilkan lagi")
    }

    private func snooze(_ bill: OverdueCardBill) {
        withAnimation(.settle(0.42)) { _ = later.insert(bill.id) }
        guard !bill.id.hasPrefix("preview-") else { return }
        let text = NotificationManager.lateText(card: bill.card, statement: bill.statement)
        Task {
            await NotificationManager.shared.snoozeLateReminder(
                cardId: bill.card.id, statementDate: bill.statement.statementDate, title: text.title, body: text.body)
        }
    }
}
