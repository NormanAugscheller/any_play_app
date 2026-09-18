import Testing
import Foundation

/// The interface follows the system language. These tests read the translation files
/// and the app's source directly, so a forgotten key fails the build instead of
/// showing up as a raw identifier on someone's screen.
@Suite("Localization")
struct LocalizationTests {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func strings(_ language: String) throws -> [String: String] {
        let url = root.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    /// Every literal key passed to L10n.tr in the app's sources.
    static func keysUsedInCode() throws -> Set<String> {
        let sources = root.appendingPathComponent("Sources/AnyPlay")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        let pattern = try NSRegularExpression(pattern: #"L10n\.tr\("([^"\\]+)""#)
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { keys.insert(String(text[range])) }
            }
        }
        return keys
    }

    static func placeholders(_ text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dfsu]"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    @Test("English and German contain exactly the same keys")
    func languagesMatch() throws {
        let english = try Self.strings("en")
        let german = try Self.strings("de")
        #expect(Set(english.keys) == Set(german.keys))
        #expect(!english.isEmpty)
    }

    @Test("Every key used in the code is translated")
    func noKeyMissing() throws {
        let used = try Self.keysUsedInCode()
        #expect(used.count > 40, "the key scan found suspiciously few keys: \(used.count)")
        // Built dynamically from HotkeyAction's raw values, so the scan cannot see them.
        let dynamic: Set<String> = ["hotkey.toggleOverlay", "hotkey.toggleMode", "hotkey.playPause"]
        for language in ["en", "de"] {
            let available = Set(try Self.strings(language).keys)
            let missing = used.union(dynamic).subtracting(available)
            #expect(missing.isEmpty, "\(language) is missing \(missing.sorted())")
        }
    }

    @Test("Translations keep the same placeholders as the English text")
    func placeholdersMatch() throws {
        let english = try Self.strings("en")
        let german = try Self.strings("de")
        for (key, value) in english {
            #expect(Self.placeholders(value) == Self.placeholders(german[key] ?? ""),
                    "placeholders differ for \(key)")
        }
    }
}
