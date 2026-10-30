import Foundation

/// "Gaji masuk lebih awal": when a salary is recorded before payday the user must say whether the new period starts on its
/// date. Only income in the built-in Gaji category asks; the choice is kept on the transaction (`starts_period`).
enum EarlySalary {
    static let categoryKey = "income_salary"

    static func applies(type: Transaction.TransactionType, category: Category?, date: Date, cycle: PaydayCycle = .current) -> Bool {
        type == .income && category?.systemKey == categoryKey && cycle.isEarlySalary(date)
    }

    /// Adds the chosen date to the shifts mirrored on the device, so periods change at once without waiting for a refresh.
    /// It does not announce the change: the save is still adding the amount to the wallet, and the screen that saved
    /// announces once everything is written. Announcing here made Beranda reload balances before that last step.
    @MainActor
    static func remember(_ date: Date) {
        var shifts = PaydaySetting.shifts
        if !shifts.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) { shifts.append(date) }
        PaydaySetting.shifts = shifts
    }
}

extension DraftStore {
    /// A draft that still has to be asked the early-salary question before it can be saved.
    func needsPeriodChoice(_ draft: Draft) -> Bool {
        draft.kind == .income && draft.startsPeriod == nil
            && EarlySalary.applies(type: .income, category: categories.first { $0.id == draft.categoryId }, date: draft.date)
    }
}
