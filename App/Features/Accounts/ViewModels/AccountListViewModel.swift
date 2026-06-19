import Foundation

@MainActor
final class AccountListViewModel: ObservableObject {
    @Published var accounts: [Account] = []
    @Published var totalBalance: Double = 0

    func loadAccounts() {
        accounts = Account.sample
        totalBalance = accounts.reduce(0) { $0 + $1.balance }
    }
}
