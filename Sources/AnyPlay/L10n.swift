// L10n.swift — every piece of text the interface shows goes through here.
//
// The interface follows the system language (System Settings → General → Language &
// Region, or the per-app language setting). English is the development language;
// the translations live in Resources/<language>.lproj/Localizable.strings. A test
// checks that every key used in the code exists in every language.

import Foundation

enum L10n {

    /// Looks up `key`. With arguments, the translation is a printf-style format.
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
