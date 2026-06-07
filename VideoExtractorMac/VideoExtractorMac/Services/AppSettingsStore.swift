import Foundation

enum AppSettingsStore {
    private static let key = "VideoExtractorMac2.AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            var defaults = AppSettings.defaults
            defaults.defaultDownloadDirectoryPath = FileManagerService.shared.downloadsDirectory.path
            return defaults
        }

        if settings.defaultDownloadDirectoryPath.isEmpty {
            var updated = settings
            updated.defaultDownloadDirectoryPath = FileManagerService.shared.downloadsDirectory.path
            return updated
        }

        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
