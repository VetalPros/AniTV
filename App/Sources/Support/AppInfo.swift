import Foundation

/// Build-time facts the UI is allowed to show.
enum AppInfo {
    /// Marketing version from the generated Info.plist (fallback keeps previews and tests valid).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
