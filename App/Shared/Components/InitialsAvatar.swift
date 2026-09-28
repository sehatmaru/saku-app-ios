import SwiftUI

/// Round initials avatar on appPrimary.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 34
    var fontSize: CGFloat = 13

    var body: some View {
        Text(initials)
            .font(.app(fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.appPrimary, in: Circle())
    }
}
