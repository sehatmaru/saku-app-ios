import SwiftUI

struct DraftImageItem: Identifiable {
    let id: UUID
}

/// The picture a draft was read from, full screen: pinch or double-tap to zoom.
struct DraftImageViewer: View {
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = DraftImageStore.image(id) {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: geo.size.width * scale, height: geo.size.height * scale)
                            .gesture(MagnifyGesture()
                                .onChanged { scale = min(max(settled * $0.magnification, 1), 5) }
                                .onEnded { _ in settled = scale })
                            .onTapGesture(count: 2) {
                                withAnimation(.settle(0.3)) { scale = scale > 1 ? 1 : 2.5; settled = scale }
                            }
                    }
                }
            } else {
                Text(L("Gambar tidak ditemukan")).font(.app(15)).foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(.white.opacity(0.18), in: Circle())
                    .frame(width: 44, height: 44)
            }
            .padding(.trailing, 12).padding(.top, 4)
            .accessibilityLabel(L("Tutup"))
        }
    }
}
