import SwiftUI

struct CustomIconSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var selectedColor: WalletIcon.PresetColor
    @State private var showValidationAlert = false

    let onSave: (String, String) -> Void

    init(onSave: @escaping (String, String) -> Void) {
        self.onSave = onSave
        self._selectedColor = State(initialValue: WalletIcon.presetColors[3])
    }

    private var isValid: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                // Preview
                VStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 72, height: 72)
                        .overlay {
                            if isValid {
                                Text(text.trimmingCharacters(in: .whitespaces).uppercased())
                                    .font(.jakarta(16, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.jakarta(20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                }
                .padding(.top, Spacing.xl)

                // Text Input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Teks Icon")
                        .font(.jakarta(13, weight: .medium))
                        .foregroundColor(.appTextSecondary)

                    TextField("Max 4 huruf", text: $text)
                        .font(.jakarta(17, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.appGroupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onChange(of: text) { _, newValue in
                            if newValue.count > 4 {
                                text = String(newValue.prefix(4))
                            }
                        }
                }
                .padding(.horizontal, Spacing.xl)

                // Color Picker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Warna")
                        .font(.jakarta(13, weight: .medium))
                        .foregroundColor(.appTextSecondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(WalletIcon.presetColors) { preset in
                            Button {
                                selectedColor = preset
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 48, height: 48)
                                    .overlay {
                                        if selectedColor == preset {
                                            Image(systemName: "checkmark")
                                                .font(.jakarta(14, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Simpan") {
                        guard isValid else {
                            showValidationAlert = true
                            return
                        }
                        onSave(
                            text.trimmingCharacters(in: .whitespaces).uppercased(),
                            selectedColor.name
                        )
                        dismiss()
                    }
                    .font(.jakarta(15, weight: .semibold))
                }
            }
            .alert("Perhatian", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Masukkan teks untuk icon.")
            }
        }
        .presentationDetents([.medium])
    }
}
