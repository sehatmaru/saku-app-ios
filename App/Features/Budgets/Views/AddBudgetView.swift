import SwiftUI

struct AddBudgetView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String?, Double) async -> BudgetAddResult

    @State private var nameText = ""
    @State private var amountDigits = ""
    @State private var selectedIcon = "tag.fill"
    @State private var showIconPicker = false
    @State private var showValidationAlert = false
    @State private var validationMessage = ""
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    private static let iconOptions: [String] = [
        "cart", "bag", "tshirt", "gamecontroller", "car", "heart", "stethoscope",
        "book", "graduationcap", "house", "bolt.fill", "drop.fill", "pawprint",
        "airplane", "gift", "wifi", "phone", "dumbbell", "music.note", "film",
        "sportscourt", "scissors", "hammer", "fork.knife", "cup.and.saucer",
        "wineglass", "basketball.fill", "figure.walk", "briefcase", "banknote",
        "dollarsign.circle", "chart.line.uptrend.xyaxis", "arrow.left.arrow.right",
        "ellipsis", "tag.fill",
    ]

    private var amountValue: Int { Int(amountDigits) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            amountSection
                .padding(.top, 12)

            VStack(spacing: 0) {
                Button { showIconPicker = true } label: {
                    DetailRow(label: "Ikon", value: "Ganti", icon: selectedIcon, iconColor: .appText, showsChevron: true)
                }
                .buttonStyle(RowPressStyle())

                HStack(spacing: 12) {
                    Text("Nama")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 76, alignment: .leading)
                    TextField("cth: Transport Online", text: $nameText)
                        .font(.app(16, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                    if !nameText.isEmpty {
                        Button { nameText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.appTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hapus nama")
                    }
                }
                .frame(height: 52)
                .padding(.leading, 24)
                .padding(.trailing, 20)
                .rowSeparator()
            }
            .padding(.top, 20)

            Spacer(minLength: 12)

            AmountPad(color: .appPrimary, isEnabled: canSave, isSaving: isSaving, onPress: press, onSave: save)
                .disabled(isSaving)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .background(Color.appBackground)
        .alert("Perhatian", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(validationMessage) }
        .sheet(isPresented: $showIconPicker) { iconPickerContent }
    }

    private var topBar: some View {
        HStack {
            Button("Batal") { dismiss() }
                .font(.app(17))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text("Tambah budget")
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appText)
            Spacer()
            Color.clear.frame(width: 60, height: 1)
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    // MARK: Amount

    private var amountSection: some View {
        VStack(spacing: 4) {
            Text("Batas per bulan")
                .font(.app(15))
                .foregroundStyle(Color.appTextSecondary)
            HeroAmount(value: Double(amountValue), size: .large,
                       color: amountValue > 0 ? .appText : .appTextTertiary)
                .accessibilityElement()
                .accessibilityLabel("Nominal Rp\(amountValue)")
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { isNameFocused = false }
    }

    private func press(_ key: String) {
        isNameFocused = false
        guard let next = NumberPad.apply(key, to: amountValue) else { return }
        withAnimation(.snappy(duration: 0.2)) { amountDigits = next > 0 ? String(next) : "" }
    }

    // MARK: Icon Picker

    private var iconPickerContent: some View {
        PickerSheet(title: "Pilih ikon", onDone: { showIconPicker = false }) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                ForEach(Self.iconOptions, id: \.self) { icon in
                    let isOn = selectedIcon == icon
                    Button {
                        selectedIcon = icon
                        showIconPicker = false
                    } label: {
                        Circle()
                            .fill(isOn ? Color.appText : Color.appFill)
                            .frame(width: 54, height: 54)
                            .overlay {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                            }
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(icon)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
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
