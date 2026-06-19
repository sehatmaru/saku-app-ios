import Foundation

@MainActor
final class TransactionListViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []

    func loadTransactions() {
        transactions = Transaction.sample.sorted { $0.date > $1.date }
    }
}
