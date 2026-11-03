import SwiftUI

/// The one drawing of a category's colour and icon: a round badge in lists, a small chip in form rows.
/// Bright category colours take a dark glyph. Without a category it shows `fallbackIcon` on a neutral fill.
struct CategorySwatch: View {
    enum Style {
        case circle(CGFloat)
        case chip
    }

    let category: Category?
    var fallbackIcon: String = "tag"
    var style: Style = .chip

    private var fill: Color? { category.map { Color(hex: $0.color ?? "#6E6E73") } }
    private var glyph: String { category?.icon ?? fallbackIcon }
    private var ink: Color {
        guard let fill else { return .appTextSecondary }
        return fill.isLight ? Color(hex: "3D2E00") : .white
    }

    var body: some View {
        switch style {
        case .circle(let size):
            Circle()
                .fill(fill ?? Color.appFill)
                .frame(width: size, height: size)
                .overlay { Image(systemName: glyph).font(.system(size: size * 0.48)).foregroundStyle(ink) }
        case .chip:
            RoundedRectangle(cornerRadius: 4)
                .fill(fill ?? Color.appFill)
                .frame(width: 24, height: 17)
                .overlay { Image(systemName: glyph).font(.system(size: 10, weight: .semibold)).foregroundStyle(ink) }
        }
    }
}
