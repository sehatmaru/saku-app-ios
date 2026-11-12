import UIKit

/// The pictures behind photo drafts. They stay on this phone only so the draft card can open them again; a file is
/// named after `Draft.imageId` and goes once no draft points at it (`DraftStore.pruneImages`).
enum DraftImageStore {
    private static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SmartTracker.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("DraftImages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    // NSCache is thread-safe
    nonisolated(unsafe) private static let thumbnails = NSCache<NSUUID, UIImage>()

    private static func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".jpg") }

    /// Keeps the picture as a JPEG and returns its id (nil when it could not be written).
    static func save(_ image: CGImage) -> UUID? {
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.7) else { return nil }
        let id = UUID()
        do { try data.write(to: file(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) } catch { return nil }
        return id
    }

    static func image(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: file(id).path) }

    static func thumbnail(_ id: UUID) -> UIImage? {
        if let cached = thumbnails.object(forKey: id as NSUUID) { return cached }
        guard let full = image(id), let small = full.preparingThumbnail(of: CGSize(width: 132, height: 132 * full.size.height / max(full.size.width, 1))) else { return nil }
        thumbnails.setObject(small, forKey: id as NSUUID)
        return small
    }

    /// Deletes every picture no draft points at. A file younger than a minute stays: it may belong to a result sheet
    /// that has not queued its drafts yet.
    static func prune(keeping ids: Set<UUID>, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), !ids.contains(id) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > 60 { try? FileManager.default.removeItem(at: url) }
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
        thumbnails.removeAllObjects()
    }
}
