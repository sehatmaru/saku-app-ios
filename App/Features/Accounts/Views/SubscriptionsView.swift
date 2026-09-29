import SwiftUI

/// Every subscription across wallets: monthly and yearly totals, what renews next, price
/// increases. Pushed from the Dompet page's "Tagihan berulang" row.
struct SubscriptionsView: View {
    let accounts: [Account]
    let categories: [Category]
    /// Called after a subscription is added, edited or removed, so the caller reloads.
    let onChange: () -> Void

    @State private var subscriptions: [CardSubscription]
    @State private var editing: CardSubscription?
    @State private var showAdd = false

    init(accounts: [Account], subscriptions: [CardSubscription], categories: [Category], onChange: @escaping () -> Void) {
        self.accounts = accounts
        self.categories = categories
        self.onChange = onChange
        _subscriptions = State(initialValue: subscriptions)
    }

    private var active: [CardSubscription] {
        subscriptions.filter(\.isActive)
            .sorted { ($0.nextBillingDateAsDate ?? .distantFuture) < ($1.nextBillingDateAsDate ?? .distantFuture) }
    }

    private var paused: [CardSubscription] { subscriptions.filter { !$0.isActive } }
    private var monthlyTotal: Double { active.reduce(0) { $0 + $1.monthlyAmount } }
    private var yearlyTotal: Double { active.reduce(0) { $0 + $1.yearlyAmount } }

    var body: some View {
        ScrollView {
            if subscriptions.isEmpty {
                VStack(spacing: 24) {
                    EmptyMessage(icon: "repeat", title: "Belum ada langganan",
                                 message: "Catat Netflix, Spotify, cicilan aplikasi dan tagihan rutin lain supaya kamu tahu totalnya tiap bulan.")
                    EmptyStateButton(title: "Tambah langganan") { showAdd = true }
                }
                .padding(.horizontal, 24)
                .padding(.top, 120)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if !active.isEmpty {
                        SectionDivider()
                        section("Berikutnya", active)
                    }
                    if !paused.isEmpty {
                        SectionDivider()
                        section("Dijeda", paused)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color.appBackground)
        .navigationTitle("Tagihan berulang")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").foregroundStyle(Color.appPrimary)
                }
                .accessibilityLabel("Tambah langganan")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddSubscriptionView(categories: categories, accounts: accounts.filter { !$0.isArchived }) { changed() }
                .presentationDetents([.fraction(0.68), .large])
        }
        .sheet(item: $editing) { sub in
            AddSubscriptionView(categories: categories, accounts: accounts, existing: sub) { changed() }
                .presentationDetents([.fraction(0.68), .large])
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                HeroAmount(value: monthlyTotal)
                Text("/bulan")
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
            }
            Text("Rp\(yearlyTotal.formattedAsDigits()) per tahun")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .monospacedDigit()
                .padding(.top, 4)
            Text("\(active.count) langganan aktif")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 2)
            if let insight {
                Text(insight)
                    .font(.app(15))
                    .foregroundStyle(Color.appBody)
                    .lineSpacing(3)
                    .padding(.top, 18)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private var insight: String? {
        guard !active.isEmpty else { return nil }
        var text = "Setahun kamu bayar Rp\(yearlyTotal.formattedAsDigits()) untuk langganan."
        if active.count > 1, let top = active.max(by: { $0.monthlyAmount < $1.monthlyAmount }) {
            text += " Paling mahal \(top.name), Rp\(top.yearlyAmount.formattedAsDigits()) per tahun."
        }
        return text
    }

    // MARK: Rows

    private func section(_ title: String, _ subs: [CardSubscription]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 4)
            ForEach(subs) { sub in
                Button { editing = sub } label: { row(sub) }
                    .buttonStyle(RowPressStyle())
            }
        }
    }

    private func row(_ sub: CardSubscription) -> some View {
        HStack(spacing: 14) {
            Image(systemName: categories.first { $0.id == sub.categoryId }?.icon ?? "repeat")
                .font(.system(size: 20))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(sub.name)
                    .font(.app(16))
                    .foregroundStyle(Color.appText)
                    .lineLimit(1)
                Text(caption(sub))
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                    .lineLimit(1)
                if let increase = sub.priceIncrease {
                    Text("Naik Rp\(increase.formattedAsDigits())")
                        .font(.app(13, weight: .medium))
                        .foregroundStyle(Color.appError)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            Text("Rp\(sub.amount.formattedAsDigits())" + (sub.frequency == .monthly ? "/bln" : "/thn"))
                .font(.app(15, weight: .medium))
                .foregroundStyle(Color.appText)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .rowSeparator()
        .contentShape(Rectangle())
        .opacity(sub.isActive ? 1 : 0.5)
    }

    private func caption(_ sub: CardSubscription) -> String {
        let wallet = accounts.first { $0.id == sub.accountId }?.name ?? "Dompet"
        guard let date = sub.nextBillingDateAsDate else { return wallet }
        let f = DateFormatter(); f.dateFormat = "d MMM"; f.locale = Locale(identifier: "id_ID")
        guard sub.isActive else { return "\(wallet) · \(f.string(from: date))" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        let when = switch days {
        case ..<0: "lewat \(-days) hari"
        case 0: "hari ini"
        case 1: "besok"
        default: "\(days) hari lagi"
        }
        return "\(wallet) · \(f.string(from: date)) (\(when))"
    }

    // MARK: Sync

    private func changed() {
        onChange()
        Task {
            if let fresh = try? await SupabaseRepository.shared.fetchSubscriptions(accountIds: accounts.map(\.id)) {
                subscriptions = fresh
            }
        }
    }
}
