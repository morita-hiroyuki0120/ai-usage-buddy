import Foundation
import Combine

/// ローカライズ文字列の取得を担うマネージャ。
/// SPM の Resources 内 ja.lproj / en.lproj を直接参照し、
/// システム言語への自動追従と手動上書きの両方に対応する。
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public var currentLanguage: AppLanguage

    /// 手動上書き。nil の場合はシステム言語に追従する。
    @Published public var override: AppLanguage? {
        didSet {
            if override != oldValue {
                currentLanguage = resolvedLanguage(for: override)
                persistOverride()
            }
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.decodeStoredLanguage(defaults)
        self.override = stored
        self.currentLanguage = Self.resolvedLanguageStatic(for: stored, defaults: defaults)
    }

    /// オーバーライドを解除してシステム言語へ戻す。
    public func resetToSystemLanguage() {
        override = nil
        currentLanguage = Self.resolvedLanguageStatic(for: nil, defaults: defaults)
    }

    /// キーに対応する文字列を現在の言語で返す。
    public func t(_ key: String) -> String {
        string(key: key, language: currentLanguage)
    }

    /// キーに対応する文字列を指定言語で返す（テスト用）。
    public func string(key: String, language: AppLanguage) -> String {
        if let bundle = Self.lprojBundle(for: language, module: Bundle.module) {
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            if value != key {
                return value
            }
        }
        // フォールバック: 英語 → キーそのもの
        if let en = Self.lprojBundle(for: .english, module: Bundle.module) {
            let value = en.localizedString(forKey: key, value: nil, table: nil)
            if value != key {
                return value
            }
        }
        return key
    }

    // MARK: - Private

    private func persistOverride() {
        if let override {
            defaults.set(override.rawValue, forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    private func resolvedLanguage(for override: AppLanguage?) -> AppLanguage {
        Self.resolvedLanguageStatic(for: override, defaults: defaults)
    }

    private static let storageKey = "com.aiusagebuddy.app.languageOverride"

    private static func decodeStoredLanguage(_ defaults: UserDefaults) -> AppLanguage? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return AppLanguage(rawValue: raw)
    }

    private static func resolvedLanguageStatic(for override: AppLanguage?, defaults: UserDefaults) -> AppLanguage {
        if let override { return override }
        let preferred: [String] = defaults.array(forKey: "AppleLanguages") as? [String]
            ?? Locale.preferredLanguages
        for lang in preferred {
            if lang.hasPrefix("ja") { return .japanese }
            if lang.hasPrefix("en") { return .english }
        }
        return .english
    }

    /// モジュールバンドル内の指定言語 lproj バンドルを返す。
    static func lprojBundle(for language: AppLanguage, module: Bundle) -> Bundle? {
        let name = "\(language.rawValue).lproj"
        if let url = module.url(forResource: name, withExtension: nil) {
            return Bundle(url: url)
        }
        return nil
    }
}

/// ビューから簡潔に参照するためのショートカット。
public func L(_ key: String) -> String {
    LocalizationManager.shared.t(key)
}
