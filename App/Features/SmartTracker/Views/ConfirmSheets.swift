import SwiftUI

/// The bottom sheets of Konfirmasi catatan (design 4a): a title with a close button over a search list for
/// categories, a short list for type and wallet, the day picker, a number pad or a name field. It is a system
/// sheet (so the keyboard lifts it and leaves the page alone) that is as tall as its content.
struct ConfirmSheetBody<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 360

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L(title)).font(.app(19, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.appText)
                        .frame(width: 34, height: 34).background(Color.stChip, in: Circle())
                }
                .accessibilityLabel(L("Tutup"))
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
            content.padding(.horizontal, 20).padding(.bottom, 12)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.appBackground)
        .presentationDetents([.height(height + 20)])
        .presentationBackground(Color.appBackground)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }
}

/// A row of a pick list: round icon, name, small line, and a check that pops in on the chosen one.
struct ConfirmPickRow: View {
    let icon: String
    var iconBg: Color = .stChip
    var iconFg: Color = .appText
    let title: String
    var subtitle: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconFg)
                    .frame(width: 38, height: 38).background(iconBg, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(16)).foregroundStyle(Color.appText)
                    if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.app(13)).foregroundStyle(Color.appTextSecondary) }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.stGreen)
                    .opacity(isOn ? 1 : 0).scaleEffect(isOn ? 1 : 0.4)
                    .animation(.settle(0.26), value: isOn)
            }
            .padding(.horizontal, 10).frame(height: 56)
            .background(isOn ? Color.stSuccessBg.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.2), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ConfirmCategoryList: View {
    let categories: [Category]
    let selectedId: String?
    let onPick: (Category) -> Void
    let onCreate: (String) -> Void
    @State private var query = ""
    @State private var keyboardUp = false

    private var shown: [Category] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? categories : categories.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Color.appTextTertiary)
                TextField(L("Cari kategori"), text: $query).font(.app(16)).autocorrectionDisabled()
            }
            .padding(.horizontal, 12).frame(height: 42).background(Color.stChip, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 6)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(shown) { c in
                        ConfirmPickRow(icon: c.icon ?? "tag", title: c.name, isOn: c.id == selectedId) { onPick(c) }
                    }
                    if shown.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Tidak ada kategori “%@”", query)).font(.app(15)).foregroundStyle(Color.appTextSecondary).padding(.horizontal, 4)
                            Button { onCreate(query.trimmingCharacters(in: .whitespaces)) } label: {
                                Label(L("Buat kategori “%@”", query), systemImage: "plus")
                                    .font(.app(16, weight: .semibold)).foregroundStyle(Color.stGreen)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 52)
                                    .background(Color.stSuccessBg, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding(.vertical, 14).padding(.horizontal, 6)
                    }
                }
            }
            // as tall as its rows (the panel sits on the keyboard, so a long list would push it off the top)
            .frame(height: shown.isEmpty ? 150 : min(keyboardUp ? 170 : 360, CGFloat(shown.count) * 58))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
    }
}

struct ConfirmAmountPad: View {
    let amount: Int
    let isIncome: Bool
    let onPress: (String) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text((isIncome ? "+" : "−") + "Rp" + amount.formattedDigits())
                .font(.app(44, weight: .ultraLight)).tracking(-1.6).monospacedDigit()
                .foregroundStyle(isIncome ? Color.stGreen : Color.appText)
                .frame(height: 72).frame(maxWidth: .infinity)
            NumberPadKeys(onPress: onPress, keyHeight: 54)
            Button(action: onDone) {
                Text(L("Selesai")).font(.app(16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(amount > 0 ? Color.stGreen : Color.appTextTertiary, in: Capsule())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 6)
    }
}

private extension Int {
    func formattedDigits() -> String { Double(self).formattedAsDigits() }
}
