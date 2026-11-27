import SwiftUI

/// "Cicilan 0%": Tidak / 3 / 6 / 12 / 24 bulan. One sheet for Tambah transaksi, Detail transaksi and Draf.
struct InstallmentChoiceSheet: View {
    /// 0 means no installment.
    let selected: Int
    let onSelect: (Int) -> Void
    let onDone: () -> Void

    private static let options = [0, 3, 6, 12, 24]

    var body: some View {
        PickerSheet(title: L("Cicilan 0%"), actionTitle: L("Selesai"), onDone: onDone) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Self.options, id: \.self) { months in
                        let isOn = months == selected
                        Button { onSelect(months) } label: {
                            Text(months == 0 ? L("Tidak") : L("%lld bulan", months))
                                .font(.app(15, weight: .medium))
                                .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(isOn ? Color.appText : Color.appFill, in: Capsule())
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                Text("Seluruh nominal langsung memakai limit kartu, tapi tiap tagihan hanya menagih satu bagian.")
                    .font(.app(13))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }
}
