import SwiftUI

/// Recurring bills on one wallet (design 1b background), pushed from the card detail.
struct WalletSubscriptionsView: View {
    let account: Account
    let subscriptions: [CardSubscription]
    let categories: [Category]

    private struct Editing: Identifiable {
        let existing: CardSubscription?
        var id: String { existing?.id ?? "new" }
    }

    @State private var form: Editing?
    @State private var toastText = ""
    @State private var isToastShown = false
    @AppStorage("isBalanceVisible") private var isBalanceVisible = true

    init(account: Account, subscriptions: [CardSubscription], categories: [Category]) {
        self.account = account
        self.subscriptions = subscriptions
        self.categories = categories
    }

    private var monthlyTotal: Double {
        subscriptions.filter(\.isActive).reduce(0) { $0 + $1.monthlyAmount }
    }

    private func money(_ value: Double) -> String {
        isBalanceVisible ? value.formattedAsCurrency() : "Rp" + hiddenAmount
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if subscriptions.isEmpty {
                    emptyState
                } else {
                    totalBox
                    LazyVStack(spacing: 0) {
                        ForEach(subscriptions) { sub in
                            row(sub)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                EmptyStateButton(title: "Tambah tagihan") { form = Editing(existing: nil) }
                    .padding(.top, 20)
                    .padding(.bottom, 60)
            }
            .animation(.settle(0.46), value: subscriptions.map(\.id))
        }
        .background(Color.appBackground)
        .navigationTitle("Tagihan berulang")
        .navigationBarTitleDisplayMode(.inline)
        .toast(toastText, isShown: $isToastShown)
        .sheet(item: $form) { form in
            AddSubscriptionView(categories: categories, account: account, existing: form.existing) {
                toastText = form.existing == nil ? "Tagihan berulang ditambahkan" : "Perubahan disimpan"
                Task {
                    // After the sheet has slid away.
                    try? await Task.sleep(for: .milliseconds(300))
                    isToastShown = true
                }
            }
            .presentationDetents([.large])
        }
    }

    private var totalBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Total per bulan")
                .font(.app(13))
                .foregroundStyle(Color.appTextSecondary)
            Text(money(monthlyTotal))
                .font(.app(20, weight: .semibold))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(Color.appText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(light: 0xF7F7F8, dark: 0x1C1C1E), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Color.appFill)
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "repeat")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.appText)
                }
            Text("Belum ada tagihan berulang")
                .font(.app(20, weight: .semibold))
                .foregroundStyle(Color.appText)
                .padding(.top, 10)
            Text("Catat langganan seperti Netflix atau Spotify yang ditagih ke \(account.isCreditCard ? "kartu ini" : "dompet ini") tiap bulan.")
                .font(.app(15))
                .lineSpacing(3)
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 120)
        .padding(.bottom, 8)
    }

    private func row(_ sub: CardSubscription) -> some View {
        let category = categories.first { $0.id == sub.categoryId }
        let caption = [category?.name ?? "Lainnya", sub.frequency == .monthly ? "tiap bulan" : "tiap tahun"]
            .joined(separator: " · ")
        return Button { form = Editing(existing: sub) } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.appFill)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: category?.icon ?? "repeat")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.appBody)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text(sub.name)
                            .font(.app(16))
                            .foregroundStyle(Color.appText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(money(sub.amount))
                            .font(.app(16))
                            .monospacedDigit()
                            .foregroundStyle(sub.isActive ? Color.appText : Color.appTextSecondary)
                    }
                    HStack(spacing: 6) {
                        Text(caption)
                        if !sub.isActive {
                            Text("Dijeda")
                                .font(.app(12, weight: .medium))
                                .foregroundStyle(Color.appWarning)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(Color.appWarning.opacity(0.12), in: Capsule())
                        }
                    }
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
                }
                .frame(height: 64)
                .rowSeparator()
            }
            .padding(.horizontal, 24)
            .opacity(sub.isActive ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}
