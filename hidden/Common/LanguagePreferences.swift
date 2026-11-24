//
//  LanguagePreferences.swift
//  Hidden Bar
//
//  Copyright © 2026 Console Labs. All rights reserved.
//

import AppKit
import Foundation

/// The language Hidden Bar opens in.
///
/// The app keeps no language key of its own: it reads and writes CFBundle's
/// `AppleLanguages`, the same key macOS's per-app language panel uses, so both
/// controls always show the same value. It takes effect on the next launch,
/// which is why the row says so.
enum LanguagePreferences {
    /// CFBundle reads this key, so writing it is the whole override.
    static let appleLanguagesKey = "AppleLanguages"

    struct Language: Equatable {
        /// The localization code, such as "zh-Hans".
        let code: String
        /// The language's own name, readable while the app is in another one.
        let name: String
    }

    /// What the app ships, by native name. "Base" is not a language.
    static func languages(in bundle: Bundle = .main) -> [Language] {
        bundle.localizations
            .filter { $0 != "Base" }
            .map { Language(code: $0, name: nativeName(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func nativeName(of code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }

    /// The stored override, or nil when the app follows the system language.
    ///
    /// Read from this app's own domain, never with `stringArray(forKey:)`: that
    /// lookup falls back to the global domain, where macOS keeps the system
    /// language, so "follow the system" would read back as that language
    /// rather than as an empty list. `persistentDomain` holds only what this
    /// app wrote, so a missing key really means no override.
    static func override(in store: UserDefaults = AppDefaults.store,
                         domain: String? = AppDefaults.storeDomain) -> String? {
        guard let domain,
              let values = store.persistentDomain(forName: domain),
              let codes = values[appleLanguagesKey] as? [String],
              let code = codes.first, !code.isEmpty else { return nil }
        return code
    }

    /// Whether picking `picked` needs a relaunch: only when it differs from what
    /// is stored. Picking the language already in effect changes nothing.
    static func needsRestart(from stored: String?, to picked: String?) -> Bool {
        stored != picked
    }

    /// nil restores the system choice.
    static func setOverride(_ code: String?, in store: UserDefaults = AppDefaults.store) {
        if let code, !code.isEmpty {
            store.set([code], forKey: appleLanguagesKey)
        } else {
            store.removeObject(forKey: appleLanguagesKey)
        }
    }
}

/// Reopens the running bundle after this process exits. The helper waits for
/// this process to leave, so the new instance does not see it and quit as a
/// duplicate. Shared by the language row and the App Store migration, so there
/// is one reload script in the app.
enum AppRelaunch {
    /// The App Store build is sandboxed. The helper itself starts there, but
    /// the sandbox denies the `kill -0` that tells whether this process has
    /// left, so the language row only says the choice takes effect after a
    /// restart. Settings shows the button in the direct build, where it works.
    static var isAvailable: Bool {
        SettingsBuild.current == .direct
    }

    /// Waits until `pid` is gone, then opens `url`.
    static func arguments(for url: URL, pid: Int32) -> [String] {
        ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
         "sh", String(pid), url.path]
    }

    /// True once the helper is running and this process is quitting. A helper
    /// that cannot start leaves the app open: quitting then would close it with
    /// nothing left to reopen it.
    @discardableResult
    static func now(at url: URL = Bundle.main.bundleURL) -> Bool {
        guard isAvailable, AppDefaults.allowsHostSideEffects else { return false }
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = arguments(for: url, pid: ProcessInfo.processInfo.processIdentifier)
        do {
            try waiter.run()
        } catch {
            NSLog("AppRelaunch: relaunch failed: \(error.localizedDescription)")
            return false
        }
        NSApp.terminate(nil)
        return true
    }
}
