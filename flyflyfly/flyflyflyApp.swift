import SwiftUI

@main
struct flyflyflyApp: App {
    @StateObject private var languageManager = LanguageManager.shared
    
    // 使用一個變數來強制視圖刷新
    @State private var languageId = UUID()
    
    init() {
        AppDiagnostics.shared.setupIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 雙重保證：id 改變會強制重建，locale 改變會強制翻譯
                .id(languageId)
                .environment(\.locale, .init(identifier: languageManager.selectedLanguage))
                .onReceive(languageManager.objectWillChange) { _ in
                    // 延遲一下確保 UserDefaults 已寫入
                    DispatchQueue.main.async {
                        self.languageId = UUID()
                    }
                }
        }
        .commands {
            CommandMenu("Language") {
                ForEach(languageManager.supportedLanguages, id: \.1) { name, code in
                    Button(action: {
                        languageManager.selectedLanguage = code
                    }) {
                        HStack {
                            Text(name)
                            if languageManager.selectedLanguage == code {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }
}
