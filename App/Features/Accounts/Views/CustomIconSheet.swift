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
        VStack(spacing: 0) {
            HStack {
                Button("Batal") { dismiss() }
                    .font(.app(17))
                    .foregroundStyle(Color.appTextSecondary)
                Spacer()
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
                .font(.app(17, weight: .semibold))
                .foregroundStyle(Color.appPrimary)
            }
            .overlay {
                Text("Ikon custom")
                    .font(.app(17, weight: .semibold))
                    .foregroundStyle(Color.appText)
            }
            .frame(height: 48)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Preview
                    Circle()
                        .fill(selectedColor.color)
                        .frame(width: 72, height: 72)
                        .overlay {
                            if isValid {
                                Text(text.trimmingCharacters(in: .whitespaces).uppercased())
                                    .font(.app(17, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "questionmark")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .accessibilityHidden(true)

                    Text("Teks ikon")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 28)

                    TextField("Maks. 4 huruf", text: $text)
                        .font(.app(17, weight: .medium))
                        .foregroundStyle(Color.appText)
                        .multilineTextAlignment(.center)
                        .frame(height: 48)
                        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > 4 {
                                text = String(newValue.prefix(4))
                            }
                        }

                    Text("Warna")
                        .font(.app(15))
                        .foregroundStyle(Color.appTextSecondary)
                        .padding(.top, 24)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(WalletIcon.presetColors) { preset in
                            let isOn = selectedColor == preset
                            Button {
                                selectedColor = preset
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if isOn {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .padding(3)
                                    .overlay { if isOn { Circle().stroke(preset.color, lineWidth: 2) } }
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Color.appBackground)
        .alert("Perhatian", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Masukkan teks untuk icon.")
        }
        .presentationDetents([.medium])
        .background(Color.appBackground)
    }
}
