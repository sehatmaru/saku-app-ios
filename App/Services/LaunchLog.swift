import Foundation // TEMP-LAUNCH-LOG
 // TEMP-LAUNCH-LOG
enum LaunchLog { // TEMP-LAUNCH-LOG
    nonisolated(unsafe) static var startUptime: TimeInterval = 0 // TEMP-LAUNCH-LOG
 // TEMP-LAUNCH-LOG
    static func begin() { // TEMP-LAUNCH-LOG
        startUptime = ProcessInfo.processInfo.systemUptime // TEMP-LAUNCH-LOG
        mark("app init") // TEMP-LAUNCH-LOG
    } // TEMP-LAUNCH-LOG
 // TEMP-LAUNCH-LOG
    static func mark(_ step: String) { // TEMP-LAUNCH-LOG
        let elapsed = Int(((ProcessInfo.processInfo.systemUptime - startUptime) * 1_000).rounded()) // TEMP-LAUNCH-LOG
        print("[LAUNCH] \(step) +\(max(elapsed, 0))ms") // TEMP-LAUNCH-LOG
    } // TEMP-LAUNCH-LOG
} // TEMP-LAUNCH-LOG
