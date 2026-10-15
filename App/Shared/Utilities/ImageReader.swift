import Foundation
import ImageIO
import Vision

/// Reads the text in a picture on the device (Vision). The picture stays in memory only and is never saved or sent.
/// Compiled into the app and the share extension.
enum ImageReader {
    /// A piece of text and where it sits (Vision coordinates: origin bottom-left, 0...1).
    struct Piece { let text: String; let box: CGRect }

    /// A smaller copy (long side 2000 px) so a big photo does not exhaust memory, especially in the extension.
    static func downscaled(_ data: Data, maxSide: Int = 2000) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxSide]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Lines of text, top to bottom. Pieces on the same visual line ("Total" ... "Rp 25.000") are joined.
    static func lines(in image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let wanted = supported.filter { $0.hasPrefix("id") || $0.hasPrefix("en") }
            if !wanted.isEmpty { request.recognitionLanguages = wanted }
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let pieces = (request.results ?? []).compactMap { item -> Piece? in
                item.topCandidates(1).first.map { Piece(text: $0.string, box: item.boundingBox) }
            }
            return merge(pieces)
        }.value
    }

    static func merge(_ pieces: [Piece]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Piece]] = []
        for piece in sorted {
            if let last = rows.last?.first, abs(last.box.midY - piece.box.midY) < max(piece.box.height, last.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ") }
    }
}
