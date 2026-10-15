import SwiftUI

/// Beranda's "Sudah kamu bayar?" for card bills past their due date (Pengingat Tagihan 1c): one
/// card per overdue bill, stacked when there are several. "Belum" folds a bill into a one-line
/// reminder until tomorrow morning; "Sudah, catat" opens Catat tagihan.
struct OverdueBillBanner: View {
    let bills: [OverdueCardBill]
    let isBalanceVisible: Bool
    let onRecord: (OverdueCardBill) -> Void

    @State private var order: [String] = []
    @State private var later: Set<String> = []
    @State private var dx: CGFloat = 0
    @State private var isDragging = false

    private let store = BillReminderStore()
    private let cardHeight: CGFloat = 184

    private var open: [OverdueCardBill] {
        order.compactMap { id in bills.first { $0.id == id && !later.contains(id) } }
    }
    private var laterBills: [OverdueCardBill] { bills.filter { later.contains($0.id) } }

    var body: some View {
        VStack(spacing: 10) {
            if !open.isEmpty { stack }
            if !laterBills.isEmpty { laterRow }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .onAppear(perform: sync)
        .onChange(of: bills.map(\.id)) { _, _ in sync() }
    }

    /// Follows the bills as they load or get paid, and re-reads which ones are snoozed.
    private func sync() {
        let ids = bills.map(\.id)
        order = order.filter(ids.contains) + ids.filter { !order.contains($0) }
        later = Set(bills.filter { store.isSnoozed(card: $0.card.id, statementDate: $0.statement.statementDate) }.map(\.id))
    }

    // MARK: Stack

    private var stack: some View {
        let cards = open
        let count = cards.count
        return VStack(spacing: 12) {
            ZStack(alignment: .top) {
                ForEach(Array(cards.enumerated()).reversed(), id: \.element.id) { position, bill in
                    card(bill, position: position, count: count)
                }
            }
            .frame(height: cardHeight + CGFloat(min(count - 1, 2)) * 12, alignment: .top)
            if count > 1 { dots(cards) }
        }
    }

    private func card(_ bill: OverdueCardBill, position: Int, count: Int) -> some View {
        let isFront = position == 0
        let depth = CGFloat(min(position, 2))
        let color = bill.card.walletColor
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                logoChip(bill.card, color: color)
                Text(count > 1 ? L("%@ sudah lewat", bill.card.name) : L("Tagihan %@ sudah lewat", bill.card.name))
                    .font(.app(15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if count > 1 {
                    Text("\(position + 1)/\(count)")
                        .font(.app(12, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(isBalanceVisible ? bill.statement.remaining.formattedAsCurrency() : "Rp" + hiddenAmount)
                .font(.app(30, weight: .light))
                .tracking(-0.8)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Jatuh tempo \(TransactionDates.dayMonth.string(from: bill.statement.dueDate)). Sudah kamu bayar?")
                .font(.app(14))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 4)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { snooze(bill) } label: {
                    Text("Belum")
                        .font(.app(15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                Button { onRecord(bill) } label: {
                    Text("Sudah, catat")
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(.white, in: Capsule())
                }
            }
            .buttonStyle(PressScaleStyle())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        // Only the front card shows its content; the ones behind show their edge.
        .opacity(isFront ? 1 : 0)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(color)
                .overlay(
                    LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 12)
        }
        .scaleEffect(isFront ? 1 : 1 - depth * 0.06, anchor: .bottom)
        .offset(y: isFront ? 0 : depth * 12)
        .offset(x: isFront && count > 1 ? dx : 0)
        .rotationEffect(.degrees(isFront && count > 1 ? Double(dx) / 26 : 0), anchor: .bottom)
        .zIndex(Double(10 - position))
        .gesture(isFront && count > 1 ? swipe : nil)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(bill.card.name), tagihan \(bill.statement.remaining.formattedAsCurrency()) lewat jatuh tempo")
    }

    private func logoChip(_ card: Account, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.white)
            .frame(width: 38, height: 24)
            .overlay {
                if let logo = card.brandLogo {
                    Image(logo).resizable().scaledToFit().frame(width: 28, height: 14)
                } else {
                    Image(systemName: card.typeSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color)
                }
            }
    }

    /// Fling the front card away to bring the next bill up; a short drag springs back.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                isDragging = true
                dx = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                guard abs(value.translation.width) > 80 else {
                    withAnimation(.settle(0.42)) { dx = 0 }
                    return
                }
                let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                withAnimation(.easeOut(duration: 0.22)) { dx = direction * 440 }
                Task {
                    try? await Task.sleep(for: .milliseconds(220))
                    var reset = SwiftUI.Transaction()
                    reset.disablesAnimations = true
                    withTransaction(reset) {
                        if let first = order.first(where: { id in open.contains { $0.id == id } }) {
                            order.removeAll { $0 == first }
                            order.append(first)
                        }
                        dx = 0
                    }
                }
            }
    }

    private func dots(_ cards: [OverdueCardBill]) -> some View {
        HStack(spacing: 6) {
            ForEach(bills.filter { b in cards.contains { $0.id == b.id } }) { bill in
                let isFront = cards.first?.id == bill.id
                Capsule()
                    .fill(isFront ? Color.appText : Color.appBorder)
                    .frame(width: isFront ? 18 : 6, height: 6)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture {
                        withAnimation(.settle(0.42)) {
                            order.removeAll { $0 == bill.id }
                            order.insert(bill.id, at: 0)
                        }
                    }
                    .accessibilityLabel(bill.card.name)
            }
            Text("Geser untuk lihat tagihan lain")
                .font(.app(12))
                .foregroundStyle(Color.appTextTertiary)
                .padding(.leading, 6)
        }
        .animation(.settle(0.42), value: cards.first?.id)
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
        let text = NotificationManager.lateText(card: bill.card, statement: bill.statement)
        Task {
            await NotificationManager.shared.snoozeLateReminder(
                cardId: bill.card.id, statementDate: bill.statement.statementDate, title: text.title, body: text.body)
        }
    }
}
