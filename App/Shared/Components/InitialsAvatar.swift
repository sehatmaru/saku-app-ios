import SwiftUI

/// Round avatar: the profile photo when there is one, otherwise initials on appPrimary.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 34
    var fontSize: CGFloat = 13
    var image: UIImage? = nil

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Text(initials)
                .font(.app(fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.appPrimary, in: Circle())
        }
    }
}
