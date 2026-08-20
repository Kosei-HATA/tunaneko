import Foundation

/// In-app localization with live switching.
/// "auto" follows the system language; otherwise forces the chosen bundle.
enum L10n {
    static let supported = ["ja", "en", "zh-Hans"]

    static var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }

    static var resolvedCode: String {
        if language != "auto" { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ja") { return "ja" }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    static func tr(_ key: String) -> String {
        if let path = Bundle.main.path(forResource: resolvedCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }
}
