import Foundation
import PetCore

final class PreferenceStore {
    let file: URL
    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Retain the legacy path so the sombrero rename preserves existing settings.
        self.file = file ?? base.appendingPathComponent("WatercolorDuck/preferences.json")
    }

    func load() -> PetPreferences {
        guard FileManager.default.fileExists(atPath: file.path) else { return PetPreferences() }
        do {
            let data = try Data(contentsOf: file)
            let preferences = try JSONDecoder().decode(PetPreferences.self, from: data)
            guard preferences.schemaVersion == 1 else {
                NSLog("Unsupported preferences version; using defaults without changing the original file")
                return PetPreferences()
            }
            return preferences.validated()
        } catch {
            // Preserve malformed input for recovery rather than overwrite it silently.
            let backup = file.deletingLastPathComponent().appendingPathComponent("preferences-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: file, to: backup)
            NSLog("Preferences could not be loaded: %@", error.localizedDescription)
            return PetPreferences()
        }
    }

    func save(_ preferences: PetPreferences) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences.validated()).write(to: file, options: .atomic)
        } catch { NSLog("Preferences could not be saved: %@", error.localizedDescription) }
    }
}
