import SwiftUI

extension Font {
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Plus Jakarta Sans ExtraBold, reserved for the Saku wordmark.
    static func wordmark(_ size: CGFloat) -> Font {
        .custom("PlusJakartaSans-Regular_ExtraBold", size: size)
    }
}
