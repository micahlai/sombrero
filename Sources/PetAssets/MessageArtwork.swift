import AppKit
import PetCore

public enum MessageArtwork {
    public static var testPhotoURL: URL? { resource("FinalDuck/5b/5b0000.png") }
    public static let polaroid: NSImage? = {
        resource("Polaroid/polaroid-frame.png").flatMap { NSImage(contentsOf:$0) }
    }()
    private static func resource(_ path: String) -> URL? {
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        let candidates = bases.flatMap { base in
            ["\(PetConstants.Assets.resourceBundle)/\(path)",
             "\(PetConstants.Assets.resourceBundle)/Contents/Resources/\(path)"]
                .map { base.appendingPathComponent($0) }
        }
        return candidates.first { FileManager.default.fileExists(atPath:$0.path) }
    }
}
