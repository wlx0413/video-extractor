import SwiftUI

@main
struct VideoExtractorMacApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(settingsViewModel)
                .preferredColorScheme(settingsViewModel.settings.appearanceMode.colorScheme)
                .frame(minWidth: 1080, minHeight: 720)
        }

        Settings {
            SettingsView(viewModel: settingsViewModel)
                .frame(width: 720)
        }
    }
}

private extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
