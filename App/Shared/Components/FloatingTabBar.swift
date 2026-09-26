import SwiftUI

enum AppTab: CaseIterable {
    case home, transactions, budget, wallet, profile

    var title: String {
        switch self {
        case .home: "Beranda"
        case .transactions: "Transaksi"
        case .budget: "Budget"
        case .wallet: "Dompet"
        case .profile: "Profil"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .transactions: "list.bullet"
        case .budget: "chart.pie"
        case .wallet: "wallet.bifold"
        case .profile: "person.crop.circle"
        }
    }

    /// `list.bullet` has no filled variant.
    var selectedIcon: String { self == .transactions ? icon : icon + ".fill" }
}

/// Glass pill with five tabs plus a detached green add button.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    item(tab)
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 62)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 8)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Color.appPrimary, in: Circle())
                    .shadow(color: Color.appPrimary.opacity(0.35), radius: 10, y: 6)
            }
            .accessibilityLabel("Tambah transaksi")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .background(alignment: .bottom) {
            LinearGradient(
                stops: [.init(color: Color.appBackground.opacity(0), location: 0),
                        .init(color: Color.appBackground, location: 0.6)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 1) {
                Image(systemName: selected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(tab.title)
                    .font(.app(10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Color.appPrimary : Color.appText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background {
                if selected {
                    Capsule().fill(Color.appPrimary.opacity(0.12))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
