//
//  LanguageManager.swift
//  DFU-Tools
//
//  语言管理器：切换语言后重启应用
//

import Cocoa

final class LanguageManager {
    
    static let shared = LanguageManager()
    
    private let languageKey = "DFU-Tools-Language"
    static let autoLanguageCode = "auto"
    
    /// 当前语言 Bundle
    private(set) var currentBundle: Bundle = Bundle.main
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: languageKey) ?? LanguageManager.autoLanguageCode
        let effective = saved == LanguageManager.autoLanguageCode ? systemPreferredLanguage() : saved
        
        // 确保 AppleLanguages 被设置，这样 Storyboard 本地化才能正确工作
        if saved != LanguageManager.autoLanguageCode {
            UserDefaults.standard.set([effective], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
        
        updateBundle(for: effective)
    }
    
    private func updateBundle(for languageCode: String) {
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            currentBundle = bundle
        } else {
            currentBundle = Bundle.main
        }
    }
    
    // MARK: - 可用语言
    
    func availableLanguages() -> [String] {
        guard let resourcePath = Bundle.main.resourcePath else { return ["en"] }
        
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: resourcePath) else { return ["en"] }
        
        var languages: [String] = []
        for item in contents where item.hasSuffix(".lproj") {
            let code = String(item.dropLast(6))
            let stringsPath = "\(resourcePath)/\(item)/Localizable.strings"
            if fileManager.fileExists(atPath: stringsPath) {
                languages.append(code)
            }
        }
        return languages.isEmpty ? ["en"] : languages.sorted()
    }
    
    func systemPreferredLanguage() -> String {
        let available = availableLanguages()
        // 获取系统语言设置并检查是否有效
        guard let systemLang = CFPreferencesCopyAppValue("AppleLanguages" as CFString, kCFPreferencesAnyApplication) as? [String],
              !available.isEmpty else {
            return available.first ?? "en"
        }

        guard let firstLang = systemLang.first?.lowercased() else {
            return available.first ?? "en"
        }
        
        if firstLang.hasPrefix("zh") {
            if firstLang.contains("hant") && available.contains("zh-Hant") { return "zh-Hant" }
            if available.contains("zh-Hans") { return "zh-Hans" }
        } else {
            let base = firstLang.components(separatedBy: "-").first ?? firstLang
            if available.contains(base) { return base }
            if let originalLang = systemLang.first, available.contains(originalLang) { return originalLang }
        }
        return available.first ?? "en"
    }
    
    func effectiveLanguage() -> String {
        let saved = UserDefaults.standard.string(forKey: languageKey) ?? LanguageManager.autoLanguageCode
        return saved == LanguageManager.autoLanguageCode ? systemPreferredLanguage() : saved
    }
    
    // MARK: - 切换语言（重启应用）
    
    func switchLanguage(_ languageCode: String) {
        UserDefaults.standard.set(languageCode, forKey: languageKey)
        
        let effectiveLang = languageCode == LanguageManager.autoLanguageCode
            ? systemPreferredLanguage()
            : languageCode
        
        UserDefaults.standard.set([effectiveLang], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        restartApp()
    }
    
    private func restartApp() {
        guard let bundlePath = Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent().path else { return }
        
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        task.launch()
        
        NSApp.terminate(nil)
    }
    
    // MARK: - 本地化字符串
    
    func string(_ key: String) -> String {
        currentBundle.localizedString(forKey: key, value: key, table: nil)
    }
    
    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = currentBundle.localizedString(forKey: key, value: key, table: nil)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - 全局函数

func L(_ key: String) -> String {
    LanguageManager.shared.string(key)
}

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = LanguageManager.shared.string(key)
    return String(format: format, arguments: arguments)
}
