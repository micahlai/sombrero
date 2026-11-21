import Foundation
import PetCore

public final class BibleLibrary {
    public let catalog: BibleCatalog?
    public let failure: String?
    public init(directory: URL? = nil) {
        let bases=[Bundle.main.resourceURL,Bundle.main.bundleURL,Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let candidates=bases.flatMap { base in
            ["\(PetConstants.Assets.resourceBundle)/Bible","\(PetConstants.Assets.resourceBundle)/Contents/Resources/Bible"].map { base.appendingPathComponent($0) }
        }
        do {
            guard let root=directory ?? candidates.first(where:{ FileManager.default.fileExists(atPath:$0.path) }) else { throw CocoaError(.fileNoSuchFile) }
            let loaded=try JSONDecoder().decode(BibleCatalog.self,from:Data(contentsOf:root.appendingPathComponent("verses.json")))
            guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
            catalog=loaded; failure=nil
        } catch { catalog=nil; failure="Bible catalog could not be loaded: \(error.localizedDescription)" }
    }
}
