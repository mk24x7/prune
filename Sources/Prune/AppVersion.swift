import Foundation

enum AppVersion {
    /// CFBundleShortVersionString of the running app, or "dev" under `swift run`.
    static var short: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}
