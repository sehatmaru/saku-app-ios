import SwiftUI

extension View {
    func appTextFieldStyle() -> some View {
        self
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
