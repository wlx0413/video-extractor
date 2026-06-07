import Foundation

enum SafePath {
    static func sanitizedFileName(_ rawValue: String, fallbackPrefix: String = "video") -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "\(fallbackPrefix)_\(timestampForFileName())" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let components = baseName.components(separatedBy: invalidCharacters)
        let sanitized = components
            .joined(separator: "_")
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        if sanitized.isEmpty {
            return "\(fallbackPrefix)_\(timestampForFileName())"
        }

        return String(sanitized.prefix(180))
    }

    static func timestampForFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }

    static func isChild(_ child: URL, of parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    static func uniqueDestination(in directory: URL, preserving fileName: String) -> URL {
        let fileManager = FileManager.default
        let candidate = directory.appendingPathComponent(fileName)

        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let source = URL(fileURLWithPath: fileName)
        let name = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let timestamp = timestampForFileName()
        let stampedName = ext.isEmpty ? "\(name)_\(timestamp)" : "\(name)_\(timestamp).\(ext)"
        let stampedCandidate = directory.appendingPathComponent(stampedName)

        guard fileManager.fileExists(atPath: stampedCandidate.path) else {
            return stampedCandidate
        }

        let uuid = UUID().uuidString.prefix(8)
        let uuidName = ext.isEmpty ? "\(name)_\(timestamp)_\(uuid)" : "\(name)_\(timestamp)_\(uuid).\(ext)"
        return directory.appendingPathComponent(uuidName)
    }
}
