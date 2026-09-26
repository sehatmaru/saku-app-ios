import SwiftUI

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String?, Double) async -> BudgetAddResult

    @State private var nameText = ""
    @State private var amountDigits = ""
    @State private var showKeyboard = false
    @State private var selectedIcon = "tag.fill"
    @State private var showIconPicker = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false

    private static let iconOptions: [String] = [
        "cart", "bag", "tshirt", "gamecontroller", "car", "heart", "stethoscope",
        "book", "graduationcap", "house", "bolt.fill", "drop.fill", "pawprint",
        "airplane", "gift", "wifi", "phone", "dumbbell", "music.note", "film",
        "sportscourt", "scissors", "hammer", "fork.knife", "cup.and.saucer",
        "wineglass", "basketball.fill", "figure.walk", "briefcase", "banknote",
        "dollarsign.circle", "chart.line.uptrend.xyaxis", "arrow.left.arrow.right",
        "ellipsis", "tag.fill",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        amountSection
                        formCard
                    }
                    .padding(Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .gesture(showKeyboard ? TapGesture().onEnded { showKeyboard = false } : nil)

                if showKeyboard {
                    AmountKeyboard(amountDigits: $amountDigits, maxDigits: 12) {
                        showKeyboard = false
                    }
                    .padding(.top, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showKeyboard)
            .background(Color.appGroupedBackground)
            .navigationTitle("Tambah Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .tint(.appPrimary)
                    } else {
                        Button("Simpan") { save() }
                            .font(.app(15, weight: .bold))
                            .foregroundColor(canSave ? .appPrimary : .appTextSecondary.opacity(0.4))
                            .disabled(!canSave)
                    }
                }
            }
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: { Text(validationMessage) }
            .onAppear { showKeyboard = true }
            .sheet(isPresented: $showIconPicker) { iconPickerContent }
        }
    }

    // MARK: Amount

    private var amountSection: some View {
        HStack(spacing: 4) {
            Text("Rp")
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Text(amountDigits.isEmpty ? "0" : amountDigits.formattedWithThousandSeparator)
                .font(.app(34, weight: .bold))
                .foregroundColor(.appText)
            Spacer()
            if !amountDigits.isEmpty {
                Button {
                    amountDigits = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.app(20))
                        .foregroundColor(.appTextSecondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { showKeyboard = true }
    }

    // MARK: Form Card

    private var formCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Button {
                    showIconPicker = true
                } label: {
                    iconCircle(selectedIcon, .appExpense)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nama Budget").font(.app(10)).foregroundColor(.appTextSecondary)
                    TextField("cth: Transport Online", text: $nameText)
                        .font(.app(15)).foregroundColor(.appText)
                }
                Spacer(minLength: 8)
                if !nameText.isEmpty { clearBtn { nameText = "" } }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 14)
        }
        .background(Color.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Rows

    private func iconCircle(_ icon: String, _ color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
            Image(systemName: icon).font(.app(14, weight: .semibold)).foregroundColor(color)
        }
    }

    private func clearBtn(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.app(16))
                .foregroundColor(.appTextSecondary.opacity(0.4))
        }
        .buttonStyle(.plain)
    }

    // MARK: Icon Picker

    private var iconPickerContent: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 6), spacing: Spacing.sm) {
                    ForEach(Self.iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            showIconPicker = false
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.appExpense.opacity(selectedIcon == icon ? 0.2 : 0.08))
                                    .frame(width: 44, height: 44)
                                Image(systemName: icon)
                                    .font(.app(17, weight: .medium))
                                    .foregroundColor(selectedIcon == icon ? .appExpense : .appTextSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
            }
            .background(Color.appGroupedBackground)
            .navigationTitle("Pilih Ikon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Tutup") { showIconPicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Save

    private var canSave: Bool {
        guard !amountDigits.isEmpty, let amount = Double(amountDigits), amount > 0 else { return false }
        return !nameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        guard let amount = Double(amountDigits), amount > 0 else {
            validationMessage = "Nominal tidak valid."; showValidationAlert = true; return
        }
        let name = nameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            validationMessage = "Nama budget tidak boleh kosong."; showValidationAlert = true; return
        }
        isSaving = true
        Task {
            let result = await onSave(name, selectedIcon, amount)
            isSaving = false
            switch result {
            case .success:
                dismiss()
            case .duplicate:
                validationMessage = "Nama budget sudah digunakan. Jika kategori sudah ada, atur budget langsung dari list."
                showValidationAlert = true
            case .failure:
                validationMessage = "Gagal menyimpan budget."
                showValidationAlert = true
            }
        }
    }
}
