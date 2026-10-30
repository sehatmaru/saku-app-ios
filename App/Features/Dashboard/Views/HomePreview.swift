import SwiftUI

/// Test builds only: shows one of the cards and banners Beranda can carry, with sample data, so each can be looked
/// at without setting up the situation. Picked in Profil > Paket Saku > Uji internal; it resets when the app restarts.
@MainActor
final class HomePreview: ObservableObject {
    static let shared = HomePreview()

    enum Kind: String, CaseIterable, Identifiable {
        case overdue, overdueMany, grace, trial2, trial1, guest, guestClosed, smart, noWallet, errorBanner, errorFull
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overdue: "Tagihan kartu lewat tempo"
            case .overdueMany: "Tagihan kartu, 2 kartu"
            case .grace: "Plus: pembayaran gagal"
            case .trial2: "Plus: trial 2 hari lagi"
            case .trial1: "Plus: trial besok"
            case .guest: "Simpan akun tamu"
            case .guestClosed: "Catatan kartu tamu ditutup"
            case .smart: "Coba Smart Tracker"
            case .noWallet: "Tambah dompet pertama"
            case .errorBanner: "Banner error"
            case .errorFull: "Layar error penuh"
            }
        }
    }

    @Published var kind: Kind?
    /// Sample bills "paid" from the banner, so its recorded animation can be watched.
    @Published private var paid: Set<String> = []

    func toggle(_ new: Kind) { kind = kind == new ? nil : new; paid = [] }

    func pay(_ id: String) { paid.insert(id) }

    static let errorMessage = "Datamu belum bisa dimuat. Periksa koneksi lalu coba lagi."

    /// One or two overdue card bills made up for the banner.
    var bills: [OverdueCardBill]? {
        all?.filter { !paid.contains($0.id) }
    }

    private var all: [OverdueCardBill]? {
        switch kind {
        case .overdue: [Self.bill(id: "preview-1", name: "BCA Visa", amount: 2_450_000, daysOverdue: 3, color: "0060AF")]
        case .overdueMany: [Self.bill(id: "preview-1", name: "BCA Visa", amount: 2_450_000, daysOverdue: 3, color: "0060AF"),
                            Self.bill(id: "preview-2", name: "Mandiri JCB", amount: 870_000, daysOverdue: 1, color: "B8860B")]
        default: nil
        }
    }

    var plusBanner: PlusBanner? {
        switch kind {
        case .grace: PlusBanner.make(.grace, until: "3 Nov")
        case .trial2: PlusBanner.make(.trialEnding(days: 2), until: "3 Nov")
        case .trial1: PlusBanner.make(.trialEnding(days: 1), until: "3 Nov")
        default: nil
        }
    }

    private static func bill(id: String, name: String, amount: Double, daysOverdue: Int, color: String) -> OverdueCardBill {
        let day: TimeInterval = 86_400
        let due = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(daysOverdue) * day)
        let card = Account(id: id, name: name, type: .credit, icon: nil, isArchived: false, isDefault: false,
                           openingBalance: 0, currentBalance: amount, creditLimit: 10_000_000, dueDate: "\(Calendar.current.component(.day, from: due))", color: color)
        let statement = CreditStatement(sampleDue: due, amount: amount, daysOverdue: daysOverdue)
        return OverdueCardBill(card: card, statement: statement)
    }
}

extension CreditStatement {
    /// An overdue statement for previews: the whole amount still owed.
    init(sampleDue due: Date, amount: Double, daysOverdue: Int) {
        let day: TimeInterval = 86_400
        statementDate = due.addingTimeInterval(-20 * day)
        dueDate = due
        nextStatementDate = due.addingTimeInterval(10 * day)
        statementAmount = amount
        paid = 0
        remaining = amount
        unbilled = 0
        currentPeriod = 0
        status = .overdue
        minimumDue = max(Self.minimumFloor, amount * Self.minimumShare)
        interestIfMinimum = (amount - minimumDue) * Self.monthlyInterest
        self.daysOverdue = daysOverdue
        bestPurchaseDate = due.addingTimeInterval(-19 * day)
        bestPurchaseDueDate = due.addingTimeInterval(30 * day)
    }
}
