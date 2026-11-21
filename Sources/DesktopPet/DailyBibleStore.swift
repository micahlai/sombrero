import Foundation
import PetCore

final class DailyBibleStore {
    let file: URL
    init(file: URL? = nil) {
        self.file=file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
            .appendingPathComponent("WatercolorDuck/daily-verses.json")
    }
    func load() -> DailyBible {
        guard FileManager.default.fileExists(atPath:file.path) else { return DailyBible() }
        do { return try JSONDecoder().decode(DailyBible.self,from:Data(contentsOf:file)) }
        catch {
            let backup=file.deletingLastPathComponent().appendingPathComponent("daily-verses-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at:file,to:backup)
            NSLog("Daily Bible history could not be loaded: %@",error.localizedDescription)
            return DailyBible()
        }
    }
    func save(_ state: DailyBible) {
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(state).write(to:file,options:.atomic)
        } catch { NSLog("Daily Bible history could not be saved: %@",error.localizedDescription) }
    }
}
