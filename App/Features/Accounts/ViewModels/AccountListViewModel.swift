import Foundation

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Double = 0

    func loadAccounts() {
        accounts = Account.sample
        recalculateBalance()
    }

    func addAccount(_ account: Account) {
        accounts.append(account)
        recalculateBalance()
    }

    func updateAccount(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        recalculateBalance()
    }

    func removeAccount(_ id: String) {
        accounts.removeAll { $0.id == id }
        recalculateBalance()
    }

    func toggleAccountArchive(_ id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let current = accounts[index]
        accounts[index] = Account(
            id: current.id,
            name: current.name,
            type: current.type,
            balance: current.balance,
            isActive: !current.isActive,
            icon: current.icon
        )
        recalculateBalance()
    }

    private func recalculateBalance() {
        totalBalance = accounts.filter { $0.isActive }.reduce(0) { $0 + $1.balance }
    }
}
