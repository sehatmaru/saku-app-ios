import SwiftUI

extension Font {
    static func jakarta(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Plus Jakarta Sans", size: size).weight(weight)
    }
}
