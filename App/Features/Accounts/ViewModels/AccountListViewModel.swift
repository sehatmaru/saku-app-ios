import Foundation

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Double = 0
    @Published var isLoading = false

    func loadAccounts(userId: String) async {
        isLoading = true
        do {
            accounts = try await SupabaseRepository.shared.fetchAccounts(userId: userId)
            recalculateBalance()
        } catch {
            accounts = []
        }
        isLoading = false
    }

    func addAccount(name: String, type: Account.AccountType, openingBalance: Double, icon: String?, userId: String) async {
        do {
            let account = try await SupabaseRepository.shared.createAccount(name: name, type: type, openingBalance: openingBalance, icon: icon, userId: userId)
            accounts.append(account)
            recalculateBalance()
        } catch {
            // silently fail
        }
    }

    func updateAccount(id: String, name: String, type: Account.AccountType, openingBalance: Double, icon: String?, isArchived: Bool) async {
        do {
            let updated = try await SupabaseRepository.shared.updateAccount(id: id, name: name, type: type, openingBalance: openingBalance, icon: icon, isArchived: isArchived)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                accounts[index] = updated
            }
            recalculateBalance()
        } catch {
            // silently fail
        }
    }

    func removeAccount(id: String) async {
        do {
            try await SupabaseRepository.shared.softDeleteAccount(id: id)
            accounts.removeAll { $0.id == id }
            recalculateBalance()
        } catch {
            // silently fail
        }
    }

    func toggleAccountArchive(id: String) async {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        do {
            try await SupabaseRepository.shared.toggleArchiveAccount(id: id, archived: !account.isArchived)
            if let index = accounts.firstIndex(where: { $0.id == id }) {
                let updated = Account(
                    id: account.id,
                    name: account.name,
                    type: account.type,
                    icon: account.icon,
                    isArchived: !account.isArchived,
                    openingBalance: account.openingBalance
                )
                accounts[index] = updated
            }
            recalculateBalance()
        } catch {
            // silently fail
        }
    }

    private func recalculateBalance() {
        totalBalance = accounts.filter { $0.isActive }.reduce(0) { $0 + $1.balance }
    }
}
