import SwiftUI

/// "Cicilan 0%": Tidak / 3 / 6 / 12 / 24 bulan. One sheet for Tambah transaksi, Detail transaksi and Draf.
struct InstallmentChoiceSheet: View {
    /// 0 means no installment.
    let selected: Int
    let onSelect: (Int) -> Void
    let onDone: () -> Void

    var body: some View {
        PickerSheet(title: L("Cicilan 0%"), actionTitle: L("Selesai"), onDone: onDone) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 10) {
                    ForEach([[0, 3, 6], [12, 24]], id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row, id: \.self) { months in chip(months) }
                            if row.count < 3 { Spacer(minLength: 0).frame(maxWidth: .infinity) }
                        }
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

    private func chip(_ months: Int) -> some View {
        let isOn = months == selected
        return Button { onSelect(months) } label: {
            Text(months == 0 ? L("Tidak") : L("%lld bulan", months))
                .font(.app(15, weight: .medium))
                .foregroundStyle(isOn ? Color.appBackground : Color.appText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isOn ? Color.appText : Color.appText.opacity(0.1), in: Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
