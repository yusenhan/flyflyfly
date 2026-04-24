import SwiftUI

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @AppStorage("selected_language") var selectedLanguage: String = "en" {
        didSet {
            applyLanguage()
            // 觸發對象更新
            objectWillChange.send()
        }
    }
    
    init() {
        applyLanguage()
    }
    
    private func applyLanguage() {
        UserDefaults.standard.set([selectedLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
    
    var currentLocale: Locale {
        Locale(identifier: selectedLanguage)
    }
    
    let supportedLanguages = [
        ("English", "en"),
        ("繁體中文", "zh-Hant"),
        ("简体中文", "zh-Hans"),
        ("Español", "es"),
        ("日本語", "ja"),
        ("한국어", "ko"),
        ("Deutsch", "de"),
        ("Tiếng Việt", "vi")
    ]
}
