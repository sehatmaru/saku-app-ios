import Foundation

enum SubscriptionBillingService {
    static func processDueBills(userId: String) async {
        do {
            let accounts = try await SupabaseRepository.shared.fetchAccounts(userId: userId)
            let creditIds = accounts
                .filter { $0.isCreditCard && $0.isActive }
                .map { $0.id }
            guard !creditIds.isEmpty else { return }

            let subscriptions = try await SupabaseRepository.shared.fetchSubscriptions(accountIds: creditIds)
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            for sub in subscriptions where sub.isActive {
                guard var billingDate = sub.nextBillingDateAsDate else { continue }
                billingDate = calendar.startOfDay(for: billingDate)
                var iterations = 0

                while billingDate <= today && iterations < 12 {
                    iterations += 1
                    let operationId = "sub_\(sub.id)_\(Self.dateString(billingDate))"

                    try await SupabaseRepository.shared.createTransaction(
                        accountId: sub.accountId,
                        categoryId: sub.categoryId,
                        amount: sub.amount,
                        type: .expense,
                        description: nil,
                        note: "Tagihan berulang: \(sub.name)",
                        date: billingDate,
                        userId: userId,
                        isCreditAccount: true,
                        clientOperationId: operationId
                    )

                    guard let next = sub.rolledNextBillingDate(from: billingDate) else { break }
                    try await SupabaseRepository.shared.updateSubscription(
                        id: sub.id,
                        name: sub.name,
                        amount: sub.amount,
                        frequency: sub.frequency,
                        nextBillingDate: Self.dateString(next),
                        isActive: sub.isActive,
                        categoryId: sub.categoryId,
                        note: sub.note
                    )
                    billingDate = calendar.startOfDay(for: next)
                }
            }
        } catch {
            print("❌ processDueBills failed: \(error)")
        }
    }

    static func resyncNotifications(userId: String) async {
        do {
            let accounts = try await SupabaseRepository.shared.fetchAccounts(userId: userId)
            let creditIds = accounts
                .filter { $0.isCreditCard && $0.isActive }
                .map { $0.id }
            guard !creditIds.isEmpty else { return }
            let subscriptions = try await SupabaseRepository.shared.fetchSubscriptions(accountIds: creditIds)
            await NotificationManager.shared.resyncAll(subscriptions: subscriptions)
        } catch {
            print("❌ resyncNotifications failed: \(error)")
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
