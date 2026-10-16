import Foundation

/// Saku Plus status (Epic 11). Named "Entitlement", not "subscription": that word already means a card's
/// recurring bill in this codebase. The server decides (`is_plus()`); this is its copy on the device.
enum PlusStatus: String, Codable {
    case free, trial, active, grace
}

/// The one place the app asks "does this account have Saku Plus?" (US8: no second path).
struct Entitlement: Equatable {
    var status: PlusStatus = .free
    /// When the paid or trial period ends; nil means no end date (the internal test switch).
    var until: Date?

    static let free = Entitlement()

    /// Trial, active and the grace period all count, until the end date passes.
    func isPlus(at now: Date = Date()) -> Bool {
        guard status != .free else { return false }
        return until.map { $0 > now } ?? true
    }

    init(status: PlusStatus = .free, until: Date? = nil) {
        self.status = status
        self.until = until
    }

    /// From the profile's own columns; anything unknown reads as free.
    init(status: String?, until: String?) {
        self.status = status.flatMap(PlusStatus.init(rawValue:)) ?? .free
        self.until = until.flatMap(AccountDeletion.parse)
    }
}

/// The device's copy of the entitlement, kept so Plus keeps working offline until its end date (US4).
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()

    private nonisolated static let statusKey = "plusStatus"
    private nonisolated static let untilKey = "plusUntil"
    private nonisolated static let testerKey = "plusIsTester"

    @Published private(set) var entitlement: Entitlement
    /// Tester accounts may use the internal switch (US8); the server checks it again.
    @Published private(set) var isTester: Bool

    var isPlus: Bool { entitlement.isPlus() }

    private init() {
        entitlement = Self.cached
        isTester = UserDefaults.standard.bool(forKey: Self.testerKey)
    }

    func apply(_ profile: UserProfile) {
        apply(Entitlement(status: profile.plusStatus, until: profile.plusUntil), isTester: profile.isTester ?? false)
    }

    func apply(_ new: Entitlement, isTester tester: Bool) {
        entitlement = new
        isTester = tester
        let defaults = UserDefaults.standard
        defaults.set(new.status.rawValue, forKey: Self.statusKey)
        defaults.set(new.until, forKey: Self.untilKey)
        defaults.set(tester, forKey: Self.testerKey)
    }

    /// Signing out: the next account starts from free.
    func reset() { apply(.free, isTester: false) }

    /// For code that cannot reach the main actor (Shortcuts intents).
    nonisolated static var cachedIsPlus: Bool { cached.isPlus() }

    private nonisolated static var cached: Entitlement {
        let defaults = UserDefaults.standard
        return Entitlement(status: defaults.string(forKey: statusKey).flatMap(PlusStatus.init(rawValue:)) ?? .free,
                           until: defaults.object(forKey: untilKey) as? Date)
    }

    /// The test switch is for builds that are not on the App Store: debug or TestFlight (US8).
    static var isInternalBuild: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}

extension PlusStatus {
    /// The short label for the Profil row and the status card.
    var title: String {
        switch self {
        case .free: L("Gratis")
        case .trial: L("Trial")
        case .active: L("Aktif")
        case .grace: L("Masa tenggang")
        }
    }
}

/// Where an account stands, for the status page and banners (design "Plus B Status").
enum PlusPhase: Equatable {
    case free, trial, active, grace
    /// Had Plus, and its end date has passed.
    case ended
}

extension Entitlement {
    func phase(at now: Date = Date()) -> PlusPhase {
        guard status != .free else { return .free }
        if let until, until <= now { return .ended }
        switch status {
        case .trial: return .trial
        case .grace: return .grace
        default: return .active
        }
    }

    /// Whole days until the end date, counting a started day as a day; nil without an end date.
    func daysLeft(at now: Date = Date()) -> Int? {
        until.map { max(0, Int(ceil($0.timeIntervalSince(now) / 86_400))) }
    }
}
