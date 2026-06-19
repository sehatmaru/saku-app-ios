import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var type: Transaction.TransactionType = .expense
    @State private var amount = ""
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var note = ""
    @State private var showAlert = false

    private let categories = Category.sample
    private let accounts = Account.sample

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipe", selection: $type) {
                        Text("Pemasukan").tag(Transaction.TransactionType.income)
                        Text("Pengeluaran").tag(Transaction.TransactionType.expense)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    HStack {
                        Text("Rp")
                            .foregroundColor(.appTextSecondary)
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad)
                            .font(.jakarta(24, weight: .bold))
                    }
                }

                Section {
                    Picker("Kategori", selection: $selectedCategory) {
                        Text("Pilih").tag(nil as Category?)
                        ForEach(categories) { category in
                            HStack {
                                Image(systemName: category.icon)
                                Text(category.name)
                            }.tag(category as Category?)
                        }
                    }

                    Picker("Akun", selection: $selectedAccount) {
                        Text("Pilih").tag(nil as Account?)
                        ForEach(accounts) { account in
                            Text("\(account.name) (\(account.balance.formattedAsCurrency()))")
                                .tag(account as Account?)
                        }
                    }

                    TextField("Catatan (opsional)", text: $note)
                }

                Section {
                    Button("Simpan") {
                        showAlert = true
                    }
                    .frame(maxWidth: .infinity)
                    .font(.jakarta(17, weight: .semibold))
                    .foregroundColor(.appPrimary)
                }
            }
            .navigationTitle("Tambah Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
            .alert("Transaksi Tersimpan", isPresented: $showAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Transaksi berhasil dicatat.")
            }
        }
    }
}
